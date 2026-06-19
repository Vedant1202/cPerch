import Testing
import Foundation
@testable import CPerchCore

// Uses swift-testing (`import Testing`), not XCTest.
//
// D1 (transcript-owned cwd) regression suite for the SessionMerger Pass-2 join.
//
// The bug (finding D1): for a registry-ABSENT session, SessionStore used to attach a
// `decodeProjectDir`-derived cwd to the transcript signal. That decode mangles
// hyphenated dirs (`/Users/x/claude-toolbar-mac` → `/Users/x/claude/toolbar/mac`).
// Because the signal's cwd is the join key in `merge`'s Pass 2 (`$0.cwd == p.cwd`),
// a live unregistered process in a hyphenated dir failed to bind and was shown
// `concluded` while running. The D1 fix makes `TranscriptReader` read the record's
// own exact cwd, so the signal reaching the merger already carries the correct path.
//
// These tests prove the JOIN at the merger boundary: a TranscriptSignal whose cwd is
// the exact hyphenated path (as the fixed reader now produces) must bind a matching
// live unregistered process. The existing `SessionMergerTests` helpers are `private`,
// so this suite defines its own synthetic-record factories (intentionally local).

@Suite("SessionMerger — D1 transcript-cwd join")
struct SessionMergerJoinTests {

    // Fixed clock so the transcript-heuristic freshness is deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func proc(pid: Int, tty: String? = nil, cwd: String?, cpu: Double = 0) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: 1, tty: tty, cwd: cwd, cpu: cpu)
    }

    private func sig(sessionId: String, cwd: String, lastRole: String? = "assistant",
                     stop: String? = nil, pending: Int = 0, text: String? = nil,
                     age: TimeInterval = 0) -> TranscriptSignal {
        TranscriptSignal(sessionId: sessionId, cwd: cwd, lastRole: lastRole,
                         lastStopReason: stop, pendingToolUses: pending, lastText: text,
                         lastActivity: now.addingTimeInterval(-age))
    }

    // AC-D1.2 — a live UNREGISTERED process (no registry entry) whose cwd equals a
    // transcript signal's cwd in a HYPHENATED dir must bind → the session is live
    // (running/needsInput), its pid is set, and it is NOT shown concluded.
    @Test func unregisteredProcessInHyphenatedDirBindsAndIsLive() {
        let cwd = "/Users/USER/Projects/my-hyphen-project"   // the exact transcript cwd
        let sessions = SessionMerger.merge(
            processes: [proc(pid: 4242, tty: "ttys007", cwd: cwd, cpu: 4.0)],  // live, unregistered
            registry: [],                                                       // no registry entry
            transcripts: [sig(sessionId: "S-HYPH", cwd: cwd, lastRole: "user",
                              stop: "tool_use", pending: 1, text: "running tests", age: 5)],
            now: now
        )

        #expect(sessions.count == 1)
        let s = try! #require(sessions.first)
        #expect(s.id == "S-HYPH")
        #expect(s.pid == 4242)                       // bound via cwd, despite no registry entry
        #expect(s.status != .concluded)              // the core D1 promise: not falsely concluded
        #expect(s.status == .running)                // fresh pending tool → running
        #expect(s.projectPath == cwd)                // the exact hyphenated path survives
        #expect(s.host == .terminal(app: "Terminal", tty: "ttys007"))
        #expect(s.latestMessage == "running tests")
    }

    // Negative control: prove the bind genuinely depends on cwd EQUALITY. If the
    // signal carried a mangled cwd (the pre-D1 behavior) it would differ from the
    // process cwd and the process would NOT bind → concluded. This pins exactly the
    // failure mode D1 fixes, at the merger boundary.
    @Test func mismatchedCwdDoesNotBindAndIsConcluded() {
        let realCwd = "/Users/USER/Projects/my-hyphen-project"
        let mangledCwd = "/Users/USER/Projects/my/hyphen/project"   // what decodeProjectDir would yield
        let sessions = SessionMerger.merge(
            processes: [proc(pid: 4242, tty: "ttys007", cwd: realCwd, cpu: 4.0)],
            registry: [],
            transcripts: [sig(sessionId: "S-HYPH", cwd: mangledCwd, lastRole: "user",
                              stop: "tool_use", pending: 1, text: "running tests", age: 5)],
            now: now
        )

        #expect(sessions.count == 1)
        let s = try! #require(sessions.first)
        #expect(s.pid == nil)                  // cwd mismatch → no bind
        #expect(s.status == .concluded)        // the broken (pre-D1) outcome, reproduced on purpose
    }
}
