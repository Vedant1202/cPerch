import Foundation
import CoreServices

// ─────────────────────────────────────────────────────────────────────────────
// SessionStore (P2) — the live detection pipeline (SPEC §3).
//
// Orchestrates the three readers + the merger into a published `[Session]` stream:
//   scan processes → read registry → read transcripts → SessionMerger.merge →
//   resolve terminal apps → carry `blockedSince` forward → apply retention → publish.
//
// Refresh is driven by an FSEvents watch on ~/.claude/{projects,sessions} (debounced)
// plus a ~3s fallback poll. Conforms to the frozen `SessionProviding` so the app (P3)
// can swap the stub for this with no UI changes.
//
// The pure decision helpers (blockedSince / retention / terminal-app resolution) are
// `static` and unit-tested; the I/O + timer/FSEvents wiring is verified via
// `swift run CPerchApp --print` against a live machine.
// ─────────────────────────────────────────────────────────────────────────────

public final class SessionStore: SessionProviding {

    // MARK: Configuration
    private let claudeDir: URL
    private var projectsDir: URL { claudeDir.appendingPathComponent("projects", isDirectory: true) }
    private var sessionsDir: URL { claudeDir.appendingPathComponent("sessions", isDirectory: true) }
    private let retentionWindow: TimeInterval
    private let retentionCap: Int
    private let recentTranscriptWindow: TimeInterval
    private let pollInterval: TimeInterval
    private let maxRecentTranscripts = 40

    // MARK: Sources
    private let processScanner = ProcessScanner()
    private let registryReader: RegistryReader
    private let transcriptReader = TranscriptReader()

    // MARK: State (lock-guarded; UI reads on main, refresh writes on `queue`)
    private let lock = NSLock()
    private var _sessions: [Session] = []
    public var sessions: [Session] { lock.lock(); defer { lock.unlock() }; return _sessions }
    public var onChange: (() -> Void)?

    // MARK: Refresh plumbing
    private let queue = DispatchQueue(label: "dev.cperch.sessionstore")
    private var eventStream: FSEventStreamRef?
    private var pollTimer: DispatchSourceTimer?
    private var debounceWork: DispatchWorkItem?

    public init(claudeDir: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude", isDirectory: true),
                retentionWindow: TimeInterval = 3 * 3600,
                retentionCap: Int = 10,
                recentTranscriptWindow: TimeInterval = 24 * 3600,
                pollInterval: TimeInterval = 3) {
        self.claudeDir = claudeDir
        self.retentionWindow = retentionWindow
        self.retentionCap = retentionCap
        self.recentTranscriptWindow = recentTranscriptWindow
        self.pollInterval = pollInterval
        self.registryReader = RegistryReader(directory: claudeDir.appendingPathComponent("sessions", isDirectory: true))
    }

    // MARK: - SessionProviding

    public func start() {
        refresh()
        startPoll()
        startFSEvents()
    }

    public func stop() {
        stopFSEvents()
        pollTimer?.cancel(); pollTimer = nil
        debounceWork?.cancel(); debounceWork = nil
    }

    // MARK: - Refresh pipeline

    /// Run the full detection pipeline once and publish. Synchronous; safe to call
    /// directly (e.g. `--print`) or from the poll/FSEvents handlers.
    public func refresh(now: Date = Date()) {
        let processes = processScanner.scan()
        let registry = registryReader.read()
        let transcripts = gatherTranscripts(registry: registry, now: now)

        var merged = SessionMerger.merge(processes: processes, registry: registry,
                                         transcripts: transcripts, now: now)
        merged = resolveTerminalApps(merged, processes: processes)

        lock.lock()
        let previous = _sessions
        var next = SessionStore.applyBlockedSince(previous: previous, merged: merged, now: now)
        next = SessionStore.applyRetention(next, now: now, window: retentionWindow, cap: retentionCap)
        let changed = next != previous
        _sessions = next
        lock.unlock()

        if changed { DispatchQueue.main.async { [weak self] in self?.onChange?() } }
    }

    // MARK: - Transcript gathering

    /// Build the transcript signal set: precise per-registry-entry reads (live sessions),
    /// plus recently-modified project transcripts (so concluded sessions still surface).
    private func gatherTranscripts(registry: [RegistryEntry], now: Date) -> [TranscriptSignal] {
        var byId: [String: TranscriptSignal] = [:]

        // 1) Registry sessions — exact path from cwd + sessionId, authoritative cwd.
        for e in registry {
            let path = transcriptPath(cwd: e.cwd, sessionId: e.sessionId)
            if let sig = transcriptReader.read(path: path, sessionId: e.sessionId, cwd: e.cwd) {
                byId[e.sessionId] = sig
            }
        }

        // 2) Recent project transcripts — for concluded sessions not in the registry.
        //    cwd is best-effort decoded from the dir name (registry sessions above win).
        for file in recentTranscriptFiles() where byId[file.sessionId] == nil {
            guard now.timeIntervalSince(file.mtime) <= recentTranscriptWindow else { continue }
            if let sig = transcriptReader.read(path: file.url.path, sessionId: file.sessionId, cwd: file.cwd) {
                byId[file.sessionId] = sig
            }
        }
        return Array(byId.values)
    }

    private func transcriptPath(cwd: String, sessionId: String) -> String {
        projectsDir.appendingPathComponent(SessionStore.encodeProjectDir(cwd))
            .appendingPathComponent("\(sessionId).jsonl").path
    }

    private struct TranscriptFile { let url: URL; let sessionId: String; let cwd: String; let mtime: Date }

    /// Top-level `projects/<enc-cwd>/<sessionId>.jsonl` files (not subagents/), most-recent first.
    private func recentTranscriptFiles() -> [TranscriptFile] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else { return [] }
        var found: [TranscriptFile] = []
        for proj in projects {
            guard (try? proj.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let items = try? fm.contentsOfDirectory(at: proj, includingPropertiesForKeys: [.contentModificationDateKey])
            else { continue }
            let cwd = SessionStore.decodeProjectDir(proj.lastPathComponent)
            for it in items where it.pathExtension == "jsonl" {
                let mtime = (try? it.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                found.append(TranscriptFile(url: it, sessionId: it.deletingPathExtension().lastPathComponent, cwd: cwd, mtime: mtime))
            }
        }
        return Array(found.sorted { $0.mtime > $1.mtime }.prefix(maxRecentTranscripts))
    }

    /// cwd → project dir name: replace "/" with "-" (Claude's encoding).
    static func encodeProjectDir(_ cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-")
    }

    /// Best-effort reverse of `encodeProjectDir`. Lossy for paths whose components contain
    /// "-" (only used for unregistered concluded sessions' display; registry sessions carry
    /// the real cwd). Carry-forward: read the transcript's own `cwd` field to make this exact.
    static func decodeProjectDir(_ dir: String) -> String {
        "/" + dir.split(separator: "-").joined(separator: "/")
    }

    // MARK: - Terminal-app resolution (closes the P1 carry-forward)

    /// Rewrite generic `HostRef.terminal(app: "Terminal", …)` hosts with the real owning app
    /// (Terminal vs iTerm2), resolved by walking the live process's ppid chain.
    private func resolveTerminalApps(_ sessions: [Session], processes: [ProcessRecord]) -> [Session] {
        guard sessions.contains(where: { if case .terminal = $0.host { return true }; return false })
        else { return sessions }
        let ancestry = SessionStore.processAncestry()
        return sessions.map { s in
            guard case let .terminal(_, tty) = s.host, let pid = s.pid else { return s }
            var s = s
            s.host = .terminal(app: SessionStore.resolveTerminalApp(forPid: pid, ancestry: ancestry), tty: tty)
            return s
        }
    }

    /// Walk `pid` up its ppid chain; return the first ancestor that is a known terminal
    /// emulator (mapped to its AppleScript name). Defaults to "Terminal" when unresolved.
    static func resolveTerminalApp(forPid pid: Int, ancestry: [Int: (ppid: Int, name: String)]) -> String {
        var current = pid
        for _ in 0..<24 {
            guard let node = ancestry[current] else { break }
            if let app = terminalAppName(fromCommand: node.name) { return app }
            if node.ppid <= 1 { break }
            current = node.ppid
        }
        return "Terminal"
    }

    /// Map a process command/path to a terminal app's AppleScript name, or nil if it isn't one.
    static func terminalAppName(fromCommand command: String) -> String? {
        let c = command.lowercased()
        if c.contains("iterm") { return "iTerm2" }
        if c.contains("/terminal.app/") || c.hasSuffix("/terminal") || command == "Terminal" { return "Terminal" }
        return nil   // other terminals (Hyper/Alacritty/kitty/WezTerm/Warp) — v0 Jumper handles Terminal/iTerm2
    }

    /// pid → (ppid, command) for every process, via `ps`. Used for ancestry resolution.
    static func processAncestry() -> [Int: (ppid: Int, name: String)] {
        guard let out = try? ProcessScanner.runCommand("/bin/ps", ["-axo", "pid=,ppid=,command="]) else { return [:] }
        var map: [Int: (ppid: Int, name: String)] = [:]
        for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int(parts[0]), let ppid = Int(parts[1]) else { continue }
            map[pid] = (ppid, String(parts[2]))
        }
        return map
    }

    // MARK: - Pure helpers (unit-tested)

    /// Carry `blockedSince` across refreshes: stamp `now` when a session first enters
    /// needs-input, keep the original timestamp while it stays needs-input, clear it otherwise.
    static func applyBlockedSince(previous: [Session], merged: [Session], now: Date) -> [Session] {
        let prevById = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return merged.map { session in
            var session = session
            if session.status == .needsInput {
                if let prev = prevById[session.id], prev.status == .needsInput, let since = prev.blockedSince {
                    session.blockedSince = since
                } else {
                    session.blockedSince = now
                }
            } else {
                session.blockedSince = nil
            }
            return session
        }
    }

    /// Keep all live sessions; keep concluded ones only within `window`, capped to the
    /// `cap` most-recent. Preserves the input ordering (the merger's needs-you-first sort).
    static func applyRetention(_ sessions: [Session], now: Date, window: TimeInterval, cap: Int) -> [Session] {
        let keptConcluded = sessions
            .filter { $0.status == .concluded && now.timeIntervalSince($0.lastActivity) <= window }
            .sorted { $0.lastActivity > $1.lastActivity }
            .prefix(cap)
        let keptIds = Set(sessions.filter { $0.status != .concluded }.map(\.id))
            .union(keptConcluded.map(\.id))
        return sessions.filter { keptIds.contains($0.id) }
    }

    // MARK: - FSEvents + poll

    private func startPoll() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        pollTimer = timer
    }

    private func startFSEvents() {
        let paths = [projectsDir.path, sessionsDir.path] as CFArray
        var context = FSEventStreamContext(version: 0,
                                            info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<SessionStore>.fromOpaque(info).takeUnretainedValue().scheduleDebouncedRefresh()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, paths,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags)
        else { return }   // FSEvents unavailable → the poll still keeps us fresh
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        eventStream = stream
    }

    private func scheduleDebouncedRefresh() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func stopFSEvents() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }
}
