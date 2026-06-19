import Testing
import Foundation
@testable import CPerchCore

// Uses swift-testing (`import Testing`), not XCTest — XCTest ships only with full
// Xcode, while Testing.framework is in the Command Line Tools.
//
// D3 · PID-reuse guard (spec §4/D3; DD-2/DD-3/DD-4). macOS recycles PIDs, so a stale
// <pid>.json plus a reused pid can show a dead session as alive and make "jump" focus
// the wrong window. SessionMerger Pass 1 now gates the registry-pid bind on a
// start-time match (`bindIsTrustworthy`); a confident mismatch DROPS the bind so the
// session resolves `concluded` (DD-4 — the real session is gone).
//
// These tests are pure: synthetic records, a fixed `now`, no FS. They also cover the
// pure `ProcessScanner.parseElapsed` `ps -o etime=` parser used to derive a live
// process's start instant.
@Suite("SessionMerger — PID-reuse guard (D3)")
struct SessionMergerReuseTests {

    // Fixed clock so start-time tolerance math is deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func proc(pid: Int, tty: String? = nil, cwd: String?,
                      cpu: Double = 0, startTime: Date? = nil) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: 1, tty: tty, cwd: cwd, cpu: cpu, startTime: startTime)
    }

    private func reg(pid: Int, sessionId: String, cwd: String, status: String?,
                     kind: String? = "interactive", startedAt: Date? = nil) -> RegistryEntry {
        RegistryEntry(pid: pid, sessionId: sessionId, cwd: cwd,
                      status: status, kind: kind, version: "1.0.0", startedAt: startedAt)
    }

    private func sig(sessionId: String, cwd: String, lastRole: String? = "assistant",
                     stop: String? = nil, pending: Int = 0, text: String? = nil,
                     age: TimeInterval = 0) -> TranscriptSignal {
        TranscriptSignal(sessionId: sessionId, cwd: cwd, lastRole: lastRole,
                         lastStopReason: stop, pendingToolUses: pending, lastText: text,
                         lastActivity: now.addingTimeInterval(-age))
    }

    // MARK: - AC-D3.1 · bindIsTrustworthy truth table (pure)

    @Test("nil process start time → trust the bind (no regression on missing data)")
    func trustsWhenProcessStartUnknown() {
        let p = proc(pid: 4242, cwd: "/a", startTime: nil)
        let e = reg(pid: 4242, sessionId: "S", cwd: "/a", status: nil, startedAt: now)
        #expect(SessionMerger.bindIsTrustworthy(process: p, entry: e))
    }

    @Test("nil entry startedAt → trust the bind")
    func trustsWhenEntryStartUnknown() {
        let p = proc(pid: 4242, cwd: "/a", startTime: now)
        let e = reg(pid: 4242, sessionId: "S", cwd: "/a", status: nil, startedAt: nil)
        #expect(SessionMerger.bindIsTrustworthy(process: p, entry: e))
    }

    @Test("both nil → trust the bind")
    func trustsWhenBothUnknown() {
        let p = proc(pid: 4242, cwd: "/a", startTime: nil)
        let e = reg(pid: 4242, sessionId: "S", cwd: "/a", status: nil, startedAt: nil)
        #expect(SessionMerger.bindIsTrustworthy(process: p, entry: e))
    }

    @Test("start times equal → trustworthy")
    func trustsWhenEqual() {
        let p = proc(pid: 4242, cwd: "/a", startTime: now)
        let e = reg(pid: 4242, sessionId: "S", cwd: "/a", status: nil, startedAt: now)
        #expect(SessionMerger.bindIsTrustworthy(process: p, entry: e))
    }

    @Test("within tolerance (either direction) → trustworthy")
    func trustsWithinTolerance() {
        let e = reg(pid: 4242, sessionId: "S", cwd: "/a", status: nil, startedAt: now)
        // +119s and -119s both inside the 120s default.
        let later = proc(pid: 4242, cwd: "/a", startTime: now.addingTimeInterval(119))
        let earlier = proc(pid: 4242, cwd: "/a", startTime: now.addingTimeInterval(-119))
        #expect(SessionMerger.bindIsTrustworthy(process: later, entry: e))
        #expect(SessionMerger.bindIsTrustworthy(process: earlier, entry: e))
    }

    @Test("exactly at tolerance boundary → trustworthy (≤)")
    func trustsAtBoundary() {
        let p = proc(pid: 4242, cwd: "/a", startTime: now.addingTimeInterval(120))
        let e = reg(pid: 4242, sessionId: "S", cwd: "/a", status: nil, startedAt: now)
        #expect(SessionMerger.bindIsTrustworthy(process: p, entry: e))
    }

    @Test("beyond tolerance → NOT trustworthy (reuse)")
    func rejectsBeyondTolerance() {
        let e = reg(pid: 4242, sessionId: "S", cwd: "/a", status: nil, startedAt: now)
        let later = proc(pid: 4242, cwd: "/a", startTime: now.addingTimeInterval(121))
        let muchLater = proc(pid: 4242, cwd: "/a", startTime: now.addingTimeInterval(3600))
        #expect(!SessionMerger.bindIsTrustworthy(process: later, entry: e))
        #expect(!SessionMerger.bindIsTrustworthy(process: muchLater, entry: e))
    }

    @Test("custom tolerance is honored")
    func honorsCustomTolerance() {
        let e = reg(pid: 4242, sessionId: "S", cwd: "/a", status: nil, startedAt: now)
        let p = proc(pid: 4242, cwd: "/a", startTime: now.addingTimeInterval(300))
        #expect(!SessionMerger.bindIsTrustworthy(process: p, entry: e))                 // default 120
        #expect(SessionMerger.bindIsTrustworthy(process: p, entry: e, tolerance: 600))  // widened
    }

    @Test("default tolerance constant is 120s")
    func toleranceDefaultIs120() {
        #expect(SessionMerger.pidReuseTolerance == 120)
    }

    // MARK: - AC-D3.2 · reuse → bind dropped → concluded, pid nil, host not 4242's tty

    @Test("reused pid (start 1h after startedAt) ⇒ concluded, pid nil, host not the 4242 terminal")
    func reusedPidDropsBindAndConcludes() {
        let cwd = "/Users/dev/Projects/api"
        let t0 = now.addingTimeInterval(-7200)   // session A started 2h ago
        // The live pid 4242 is now an unrelated genuine claude process that started 1h
        // after session A — far beyond tolerance. Give it a tty so we can prove the host
        // is NOT derived from it.
        let sessions = SessionMerger.merge(
            processes: [proc(pid: 4242, tty: "ttys004", cwd: cwd,
                             startTime: t0.addingTimeInterval(3600))],
            registry: [reg(pid: 4242, sessionId: "S-A", cwd: cwd, status: "busy", startedAt: t0)],
            transcripts: [sig(sessionId: "S-A", cwd: cwd, stop: "tool_use", text: "half-done")],
            now: now
        )

        #expect(sessions.count == 1)
        let s = try! #require(sessions.first { $0.id == "S-A" })
        #expect(s.status == .concluded)          // bind dropped → not alive → concluded (DD-4)
        #expect(s.pid == nil)                     // no live process bound
        // Host must NOT be a terminal derived from pid 4242's tty.
        #expect(s.host != .terminal(app: "Terminal", tty: "ttys004"))
        if case .terminal = s.host { Issue.record("host should not be a terminal from the reused pid") }
        // interactive kind, no live tty → desktop fallback.
        #expect(s.host == .desktop(bundleID: "com.anthropic.claudefordesktop"))
    }

    @Test("reused pid is NOT re-claimed via cwd Pass 2 (it isn't our session)")
    func reusedPidIsNotClaimedByCwd() {
        let cwd = "/Users/dev/Projects/api"
        let t0 = now.addingTimeInterval(-7200)
        // Same reuse, but a SECOND unregistered transcript shares the cwd. The dropped
        // pid must not leak into Pass 2 and claim it.
        let sessions = SessionMerger.merge(
            processes: [proc(pid: 4242, tty: "ttys004", cwd: cwd,
                             startTime: t0.addingTimeInterval(3600))],
            registry: [reg(pid: 4242, sessionId: "S-A", cwd: cwd, status: "busy", startedAt: t0)],
            transcripts: [
                sig(sessionId: "S-A", cwd: cwd, stop: "tool_use", text: "registry session"),
                sig(sessionId: "S-OTHER", cwd: cwd, lastRole: "user", stop: "tool_use",
                    pending: 1, text: "unrelated", age: 5),
            ],
            now: now
        )
        let other = try! #require(sessions.first { $0.id == "S-OTHER" })
        #expect(other.pid == nil)                 // dropped pid did not claim it via cwd
        let a = try! #require(sessions.first { $0.id == "S-A" })
        #expect(a.pid == nil)
        #expect(a.status == .concluded)
    }

    // MARK: - AC-D3.3 · start within tolerance ⇒ bound, live, terminal host (normal case)

    @Test("matching start time ⇒ bound, live, terminal host")
    func matchingStartBindsLive() {
        let cwd = "/Users/dev/Projects/api"
        let t0 = now.addingTimeInterval(-300)     // started 5m ago
        let sessions = SessionMerger.merge(
            processes: [proc(pid: 4242, tty: "ttys004", cwd: cwd, cpu: 9,
                             startTime: t0.addingTimeInterval(30))],  // +30s, within 120s
            registry: [reg(pid: 4242, sessionId: "S-A", cwd: cwd, status: "busy", startedAt: t0)],
            transcripts: [sig(sessionId: "S-A", cwd: cwd, stop: "tool_use", text: "working")],
            now: now
        )

        let s = try! #require(sessions.first { $0.id == "S-A" })
        #expect(s.pid == 4242)                    // bound
        #expect(s.status == .running)             // alive + registry busy
        #expect(s.host == .terminal(app: "Terminal", tty: "ttys004"))
        #expect(s.source == .cli)
    }

    @Test("nil start times still bind normally (back-compat default)")
    func nilStartTimesBindNormally() {
        // The existing 43 tests / other tracks don't set start times — prove that path.
        let cwd = "/Users/dev/Projects/api"
        let sessions = SessionMerger.merge(
            processes: [proc(pid: 4242, tty: "ttys004", cwd: cwd)],   // startTime nil
            registry: [reg(pid: 4242, sessionId: "S-A", cwd: cwd, status: "busy")], // startedAt nil
            transcripts: [sig(sessionId: "S-A", cwd: cwd, stop: "tool_use")],
            now: now
        )
        let s = try! #require(sessions.first { $0.id == "S-A" })
        #expect(s.pid == 4242)
        #expect(s.status == .running)
        #expect(s.host == .terminal(app: "Terminal", tty: "ttys004"))
    }

    // MARK: - ProcessScanner.parseElapsed — pure `ps -o etime=` parser

    @Test("parseElapsed handles mm:ss")
    func parsesMinutesSeconds() {
        let expected: TimeInterval = 19 * 60 + 15
        #expect(ProcessScanner.parseElapsed("19:15") == expected)
    }

    @Test("parseElapsed handles hh:mm:ss")
    func parsesHoursMinutesSeconds() {
        let expected: TimeInterval = 1 * 3600 + 2 * 60 + 3
        #expect(ProcessScanner.parseElapsed("01:02:03") == expected)
    }

    @Test("parseElapsed handles dd-hh:mm:ss")
    func parsesDaysHoursMinutesSeconds() {
        let expected: TimeInterval = 2 * 86_400 + 3 * 3600 + 4 * 60 + 5
        #expect(ProcessScanner.parseElapsed("2-03:04:05") == expected)
    }

    @Test("parseElapsed tolerates surrounding whitespace and leading zeros")
    func parsesWithWhitespace() {
        let expected: TimeInterval = 7 * 60 + 8
        #expect(ProcessScanner.parseElapsed("  07:08  ") == expected)
        #expect(ProcessScanner.parseElapsed("00:00") == 0)
    }

    @Test("parseElapsed returns nil on malformed input")
    func parseElapsedRejectsGarbage() {
        #expect(ProcessScanner.parseElapsed("") == nil)
        #expect(ProcessScanner.parseElapsed("garbage") == nil)
        #expect(ProcessScanner.parseElapsed("1:2:3:4") == nil)   // too many colon groups
        #expect(ProcessScanner.parseElapsed("12") == nil)        // bare seconds, not a ps shape
        #expect(ProcessScanner.parseElapsed("aa:bb") == nil)
    }
}
