import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ProcessScanner (P1-A) — one of the three detection sources (SPEC §3).
//
// Scans the OS process table for genuine `claude` Code sessions and emits a
// `ProcessRecord` per session (pid, ppid, tty, cwd, %CPU). The records join the
// registry/transcript sources in SessionMerger (P1-G); from here they contribute
// existence, liveness corroboration, the controlling `tty` (for the terminal jump)
// and CPU (busy-vs-idle corroboration).
//
// Two concerns are kept separate and both injectable so the parser/filter is unit-
// testable without a live machine (SPEC §6 — DI'd FS/process where it aids testing):
//   • `listProcesses` yields the raw `ps -Ao pid,ppid,tty,%cpu,command` text.
//   • `resolveCwd` maps a pid → its cwd (production: `lsof -a -p <pid> -d cwd`).
//   • `resolveStartTime` maps a pid → its start instant for the D3 PID-reuse guard
//     (production: `ps -o etime= -p <pid>`, parsed timezone-free via `parseElapsed`).
// ─────────────────────────────────────────────────────────────────────────────

/// Scans the process table for live `claude` sessions → `[ProcessRecord]`.
///
/// The production initializer shells out (`ps` + `lsof`); tests inject fixture
/// closures. Pure parsing/filtering live in static helpers so they can be exercised
/// directly. No state — `scan()` is idempotent and side-effect-light.
public struct ProcessScanner {
    /// Yields raw process-listing text shaped like
    /// `ps -Ao pid,ppid,tty,%cpu,command` (a header row then one row per process).
    public typealias ProcessListing = () throws -> String

    private let listProcesses: ProcessListing
    private let resolveCwd: (Int) -> String?
    private let resolveStartTime: (Int) -> Date?

    /// Inject a process source (and optionally cwd / start-time resolvers) — used by
    /// tests so nothing shells out. `resolveStartTime` feeds the D3 PID-reuse guard.
    public init(listProcesses: @escaping ProcessListing,
                resolveCwd: @escaping (Int) -> String? = { _ in nil },
                resolveStartTime: @escaping (Int) -> Date? = { _ in nil }) {
        self.listProcesses = listProcesses
        self.resolveCwd = resolveCwd
        self.resolveStartTime = resolveStartTime
    }

    /// Production default: shell out to `ps` for the table, `lsof` per-pid for cwd, and
    /// `ps -o etime=` per-pid for the start instant (small N — live claude pids only).
    public init() {
        self.listProcesses = { try ProcessScanner.runPS() }
        self.resolveCwd = { ProcessScanner.lsofCwd(pid: $0) }
        self.resolveStartTime = { ProcessScanner.psStartTime(pid: $0) }
    }

    /// Scan → genuine `claude` session records. On a process-listing failure returns
    /// `[]` (detection is best-effort; the merger tolerates a missing source).
    public func scan() -> [ProcessRecord] {
        guard let raw = try? listProcesses() else { return [] }
        return ProcessScanner.parse(raw).map { row in
            ProcessRecord(pid: row.pid, ppid: row.ppid, tty: row.tty,
                          cwd: resolveCwd(row.pid), cpu: row.cpu,
                          startTime: resolveStartTime(row.pid))
        }
    }

    // MARK: - Parsing

    /// One parsed `ps` row (pre-cwd; cwd is resolved separately per pid).
    struct Row: Equatable {
        let pid: Int
        let ppid: Int
        let tty: String?
        let cpu: Double
        let command: String
    }

    /// Parse `ps -Ao pid,ppid,tty,%cpu,command` text into genuine-session rows.
    /// Skips the header, blank lines, unparseable lines, and any process that isn't a
    /// genuine `claude` session (see `isGenuineClaudeSession`).
    static func parse(_ raw: String) -> [Row] {
        var rows: [Row] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let row = parseLine(String(line)) else { continue }
            guard isGenuineClaudeSession(command: row.command) else { continue }
            rows.append(row)
        }
        return rows
    }

    /// Parse a single `ps` line. The first four columns (pid, ppid, tty, %cpu) are
    /// whitespace-delimited; everything after the fourth is the command (which itself
    /// contains spaces, so we split only the leading fields). Returns nil for the
    /// header and any malformed line.
    static func parseLine(_ line: String) -> Row? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Pull the 4 leading fixed columns off the front, leaving the command intact.
        var rest = Substring(trimmed)
        func nextField() -> String? {
            while let f = rest.first, f == " " || f == "\t" { rest = rest.dropFirst() }
            guard !rest.isEmpty else { return nil }
            let start = rest.startIndex
            var end = start
            while end < rest.endIndex, rest[end] != " ", rest[end] != "\t" {
                end = rest.index(after: end)
            }
            let field = String(rest[start..<end])
            rest = rest[end...]
            return field
        }

        guard let pidStr = nextField(), let pid = Int(pidStr) else { return nil } // header → nil
        guard let ppidStr = nextField(), let ppid = Int(ppidStr) else { return nil }
        guard let ttyField = nextField() else { return nil }
        guard let cpuStr = nextField(), let cpu = Double(cpuStr) else { return nil }

        let command = String(rest).trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return nil }

        return Row(pid: pid, ppid: ppid, tty: normalizeTTY(ttyField), cpu: cpu, command: command)
    }

    /// Normalize the `ps` TTY column to a `/dev`-style name (e.g. "ttys004"), or nil
    /// when there's no controlling terminal. `ps` prints "??" (no tty) for GUI/daemon
    /// processes, and may print either "ttys004" or a bare "s004" for terminals.
    static func normalizeTTY(_ field: String) -> String? {
        if field == "??" || field == "?" || field == "-" { return nil }
        if field.hasPrefix("tty") { return field }
        return "tty" + field
    }

    // MARK: - Start-time parsing (D3 PID-reuse guard)

    /// Parse a `ps -o etime=` elapsed-time string into seconds. `etime` is timezone-free
    /// (elapsed wall-clock since the process started) in one of three shapes:
    ///   `mm:ss`        (e.g. "19:15")
    ///   `hh:mm:ss`     (e.g. "01:02:03")
    ///   `dd-hh:mm:ss`  (e.g. "2-03:04:05")
    /// Returns the elapsed seconds, or `nil` for any other/garbled shape (best-effort —
    /// the caller treats nil as "start unknown", which the merger trusts rather than
    /// regressing). Pure and side-effect-free so it's unit-testable on sample strings.
    static func parseElapsed(_ raw: String) -> TimeInterval? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Split off an optional leading `dd-` day count.
        var days = 0
        var clock = Substring(trimmed)
        if let dash = clock.firstIndex(of: "-") {
            guard let d = Int(clock[clock.startIndex..<dash]), d >= 0 else { return nil }
            days = d
            clock = clock[clock.index(after: dash)...]
        }

        // The remainder is mm:ss or hh:mm:ss.
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        var values: [Int] = []
        for p in parts {
            guard !p.isEmpty, let v = Int(p), v >= 0 else { return nil }
            values.append(v)
        }

        let hours: Int, minutes: Int, seconds: Int
        if values.count == 3 {
            (hours, minutes, seconds) = (values[0], values[1], values[2])
        } else {
            (hours, minutes, seconds) = (0, values[0], values[1])
        }
        guard minutes < 60, seconds < 60 else { return nil }

        return TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60 + seconds)
    }

    // MARK: - Filtering

    /// True iff `command` is a genuine `claude` Code session — i.e. the claude-code
    /// binary or the `claude` CLI — and NOT Claude-desktop Electron machinery or
    /// background/daemon plumbing.
    ///
    /// Grounded in real `ps` output (SPEC §3 / spike): the desktop app is the
    /// capital-C `Claude` Electron shell plus "Claude Helper", crashpad, Squirrel and
    /// ShipIt; daemons announce themselves with `claude daemon` and spawn
    /// `--bg-pty-host` / `--bg-spare` workers. Genuine sessions run a lowercase
    /// `claude` executable (CLI at `…/bin/claude` or `…/versions/<v>/claude`, or the
    /// bundled `claude-code/<v>/claude.app/Contents/MacOS/claude`). The desktop
    /// `disclaimer` launcher is kept because its command line names that real binary.
    static func isGenuineClaudeSession(command: String) -> Bool {
        // 1) Desktop Electron app + its helper/updater processes → not a session.
        let desktopMarkers = [
            "Claude.app/Contents/MacOS/Claude",                  // Electron main shell
            "Claude Helper",                                     // GPU/renderer/utility helpers
            "chrome_crashpad_handler",                           // crash reporter
            "Squirrel.framework",                                // updater framework
            "ShipIt",                                            // Squirrel installer
            "Claude Usage.app",                                  // separate usage app
        ]
        for marker in desktopMarkers where command.contains(marker) { return false }

        // 2) Daemon supervisor + its background pty/spare workers → not a user session.
        let daemonMarkers = ["claude daemon", "--bg-spare", "--bg-pty", "--bg-pty-host"]
        for marker in daemonMarkers where command.contains(marker) { return false }

        // 3) Keep anything whose command line invokes a lowercase `claude` executable.
        //    Matches the CLI (`/bin/claude`, `/versions/<v>/claude`) and the bundled
        //    claude-code binary, and the `disclaimer` wrapper that names it. Excludes
        //    the capital-C desktop `Claude` (already filtered above) and unrelated
        //    processes that merely mention "claude" in a path/flag.
        return mentionsClaudeExecutable(command)
    }

    /// True iff a whitespace-delimited token in `command` is, or ends in, a lowercase
    /// `claude` executable (`claude`, `…/claude`, or `…/MacOS/claude`). Token-based so
    /// substrings like `--user-data-dir=…/Claude` or `claude-media` don't match.
    static func mentionsClaudeExecutable(_ command: String) -> Bool {
        for token in command.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            let path = token.split(separator: "/").last.map(String.init) ?? String(token)
            if path == "claude" { return true }
        }
        return false
    }

    // MARK: - Production shell-outs

    /// `ps -Ao pid,ppid,tty,%cpu,command` — the full process table.
    static func runPS() throws -> String {
        try runCommand("/bin/ps", ["-Ao", "pid,ppid,tty,%cpu,command"])
    }

    /// `ps -o etime= -p <pid>` → the process's start instant, computed as `now − etime`
    /// (D3 PID-reuse guard). `etime` is elapsed wall-clock and therefore timezone-free
    /// (unlike `lstart`/registry `procStart`, which are TZ-ambiguous). Returns nil if ps
    /// fails, the process is gone, or the elapsed string can't be parsed — best-effort,
    /// the merger trusts an unknown start rather than regressing.
    static func psStartTime(pid: Int, now: Date = Date()) -> Date? {
        guard let out = try? runCommand("/bin/ps", ["-o", "etime=", "-p", String(pid)]),
              let elapsed = parseElapsed(out)
        else { return nil }
        return now.addingTimeInterval(-elapsed)
    }

    /// `lsof -a -p <pid> -d cwd` → the process's cwd (the trailing NAME field of the
    /// data row), or nil if lsof fails / the process is gone. lsof prints a header row
    /// then one row whose last whitespace-delimited field is the directory path.
    static func lsofCwd(pid: Int) -> String? {
        guard let out = try? runCommand("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd"])
        else { return nil }
        for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
            guard !line.hasPrefix("COMMAND") else { continue }       // header
            // FD column is "cwd"; the path is everything after it (paths can contain
            // spaces, so take the substring following the " cwd " marker when present,
            // else the last field).
            if let range = line.range(of: " cwd ") {
                let tail = line[range.upperBound...]
                // tail = "  DIR   1,15  128  100831965 /path/with maybe spaces"
                let fields = tail.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
                if fields.count == 5 { return String(fields[4]) }
            }
            let last = line.split(separator: " ", omittingEmptySubsequences: true).last
            if let last, last.hasPrefix("/") { return String(last) }
        }
        return nil
    }

    /// Run a command, capturing stdout. Throws if it can't launch; non-zero exit still
    /// returns whatever stdout was produced (ps/lsof print partial output then warn).
    static func runCommand(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
