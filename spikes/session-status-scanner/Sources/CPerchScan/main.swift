import Foundation

// cPerch — session-status spike.
// Reads Claude's own concurrent-session registry (~/.claude/sessions/<pid>.json)
// and session transcripts (~/.claude/projects/<enc-cwd>/<id>.jsonl), then derives
// a running / needs-input / concluded status for each. Prints a table.

// MARK: - Registry model (Claude's sessions/<pid>.json)

struct SessionRegistryEntry: Decodable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let status: String?       // Claude's own enum: busy | shell | idle | waiting
    let kind: String?         // interactive | bg | daemon | daemon-worker
    let entrypoint: String?
    let name: String?
}

// MARK: - Derived status

enum DerivedStatus: String {
    case running, needsInput, concluded, unknown
    var emoji: String {
        switch self {
        case .running: return "🔵"
        case .needsInput: return "🟠"
        case .concluded: return "✅"
        case .unknown: return "⚪️"
        }
    }
    var label: String {
        switch self {
        case .running: return "running"
        case .needsInput: return "needs-input"
        case .concluded: return "concluded"
        case .unknown: return "unknown"
        }
    }
}

// MARK: - Paths

let home = FileManager.default.homeDirectoryForCurrentUser
let claudeDir = home.appendingPathComponent(".claude")
let sessionsDir = claudeDir.appendingPathComponent("sessions")
let projectsDir = claudeDir.appendingPathComponent("projects")

// MARK: - Helpers

func isAlive(_ pid: Int) -> Bool {
    if pid <= 0 { return false }
    if kill(pid_t(pid), 0) == 0 { return true }
    return errno == EPERM   // process exists but we may not signal it
}

func transcriptURL(sessionId: String, cwd: String) -> URL {
    let enc = cwd.replacingOccurrences(of: "/", with: "-")
    return projectsDir.appendingPathComponent(enc).appendingPathComponent("\(sessionId).jsonl")
}

func readTail(_ url: URL, maxBytes: UInt64 = 262_144) -> String? {
    guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? fh.close() }
    guard let size = try? fh.seekToEnd() else { return nil }
    let start = size > maxBytes ? size - maxBytes : 0
    try? fh.seek(toOffset: start)
    guard let data = try? fh.readToEnd() else { return nil }
    return String(decoding: data, as: UTF8.self)
}

func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
}

func clip(_ s: String, _ n: Int) -> String {
    let one = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    return one.count <= n ? one : String(one.prefix(n - 1)) + "…"
}

func fmtAge(_ s: Double) -> String {
    if s < 90 { return "\(Int(s))s" }
    if s < 5400 { return "\(Int(s / 60))m" }
    if s < 172_800 { return "\(Int(s / 3600))h" }
    return "\(Int(s / 86_400))d"
}

// MARK: - Transcript analysis

struct TranscriptSignal {
    var lastRole: String?
    var lastStopReason: String?
    var pendingToolUses: Int
    var lastText: String?
}

func analyzeTranscript(_ url: URL) -> TranscriptSignal? {
    guard let tail = readTail(url) else { return nil }
    var real: [[String: Any]] = []
    for line in tail.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let d = line.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
        let t = o["type"] as? String
        if (t == "user" || t == "assistant"), (o["isSidechain"] as? Bool) != true {
            real.append(o)
        }
    }
    func contentArr(_ o: [String: Any]) -> [[String: Any]] {
        ((o["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
    }
    var used = Set<String>(), res = Set<String>()
    for o in real {
        for c in contentArr(o) {
            let t = c["type"] as? String
            if t == "tool_use", let id = c["id"] as? String { used.insert(id) }
            if t == "tool_result", let id = c["tool_use_id"] as? String { res.insert(id) }
        }
    }
    let pending = used.subtracting(res).count
    guard let last = real.last else {
        return TranscriptSignal(lastRole: nil, lastStopReason: nil, pendingToolUses: pending, lastText: nil)
    }
    let m = last["message"] as? [String: Any]
    var text: String?
    for o in real.reversed() {
        let mm = o["message"] as? [String: Any]
        guard (mm?["role"] as? String) == "assistant" else { continue }
        for c in (mm?["content"] as? [[String: Any]]) ?? [] {
            if (c["type"] as? String) == "text", let t = c["text"] as? String, !t.isEmpty { text = t; break }
        }
        if text != nil { break }
    }
    return TranscriptSignal(lastRole: m?["role"] as? String,
                            lastStopReason: m?["stop_reason"] as? String,
                            pendingToolUses: pending,
                            lastText: text)
}

// MARK: - The heuristic

func deriveStatus(registryStatus: String?, alive: Bool, sig: TranscriptSignal?, ageSeconds: Double) -> DerivedStatus {
    if !alive { return .concluded }                       // process gone → session ended
    switch registryStatus {                               // trust Claude's own field when present
    case "busy", "shell": return .running
    case "waiting":       return .needsInput
    case "idle":
        if let s = sig, s.pendingToolUses > 0 { return .needsInput }  // parked mid-tool → wants you
        return .concluded
    default: break
    }
    guard let s = sig else { return .unknown }            // fallback: infer from transcript
    // No status field (e.g. older desktop app): transcript timing is fuzzy — a busy
    // session can stay quiet for a while during a long tool call or model turn. Only
    // flag needs-input once it's been quiet long enough to almost certainly be blocked
    // on the human. (The registry `status` field above is the reliable signal; this is
    // the best-effort fallback when it's absent.)
    let stalled = ageSeconds > 120
    if s.pendingToolUses > 0 { return stalled ? .needsInput : .running }   // executing vs blocked
    switch s.lastStopReason {
    case "tool_use": return stalled ? .needsInput : .running
    case "end_turn", "stop_sequence", "max_tokens": return .concluded
    default: return s.lastRole == "user" ? (stalled ? .needsInput : .running) : .concluded
    }
}

// MARK: - Gather

struct Row {
    var status: DerivedStatus
    var project: String
    var source: String
    var pid: String
    var age: Double
    var regStatus: String
    var snippet: String
}

var rowsBySession: [String: Row] = [:]
let now = Date()

// 1) Registry = Claude's live-session list
if let files = try? FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) {
    for f in files where f.pathExtension == "json" {
        guard let data = try? Data(contentsOf: f),
              let e = try? JSONDecoder().decode(SessionRegistryEntry.self, from: data) else { continue }
        let alive = isAlive(e.pid)
        let turl = transcriptURL(sessionId: e.sessionId, cwd: e.cwd)
        let mtime = (try? turl.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let age = now.timeIntervalSince(mtime)
        let sig = analyzeTranscript(turl)
        let status = deriveStatus(registryStatus: e.status, alive: alive, sig: sig, ageSeconds: age)
        rowsBySession[e.sessionId] = Row(
            status: status,
            project: URL(fileURLWithPath: e.cwd).lastPathComponent,
            source: (e.kind ?? "?") + (alive ? "" : " (dead)"),
            pid: alive ? String(e.pid) : "—",
            age: age,
            regStatus: e.status ?? "·",
            snippet: clip(sig?.lastText ?? "", 56))
    }
}

// 2) Recent transcripts not covered by the registry (these are concluded — process gone)
var found: [(URL, String, Date)] = []
if let projects = try? FileManager.default.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) {
    for proj in projects {
        guard (try? proj.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
              let items = try? FileManager.default.contentsOfDirectory(at: proj, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
        for it in items where it.pathExtension == "jsonl" {
            let mtime = (try? it.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            found.append((it, proj.lastPathComponent, mtime))
        }
    }
}
found.sort { $0.2 > $1.2 }
for (url, projDir, mtime) in found.prefix(12) {
    let sid = url.deletingPathExtension().lastPathComponent
    if rowsBySession[sid] != nil { continue }
    let age = now.timeIntervalSince(mtime)
    let sig = analyzeTranscript(url)
    let status = deriveStatus(registryStatus: nil, alive: false, sig: sig, ageSeconds: age)
    let proj = projDir.replacingOccurrences(of: "-Users-\(NSUserName())-", with: "…/")
    rowsBySession[sid] = Row(status: status, project: clip(proj, 24), source: "transcript",
                             pid: "—", age: age, regStatus: "·", snippet: clip(sig?.lastText ?? "", 56))
}

// MARK: - Print

let rows = rowsBySession.values.sorted { $0.age < $1.age }
print("")
print("  cPerch · session scan  —  \(rows.count) sessions")
print("  🔵 running   🟠 needs-input   ✅ concluded   ⚪️ unknown")
print("  " + String(repeating: "─", count: 90))
print("  \(pad("", 2)) \(pad("status", 12)) \(pad("project", 24)) \(pad("kind", 13)) \(pad("pid", 6)) \(pad("age", 5)) reg")
for r in rows {
    print("  \(r.status.emoji) \(pad(r.status.label, 12)) \(pad(clip(r.project, 24), 24)) \(pad(r.source, 13)) \(pad(r.pid, 6)) \(pad(fmtAge(r.age), 5)) \(r.regStatus)")
    if !r.snippet.isEmpty { print("       ↳ \(r.snippet)") }
}
print("")
