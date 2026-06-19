import Testing
import Foundation
@testable import CPerchCore

// session-overcounting fix — one conversation should be one row:
//   • C2 — ProcessScanner.leafRows drops launcher/parent claude procs (keep the leaf).
//   • B1 — ProcessScanner.parseResumedFrom captures `--resume <id>`; SessionMerger drops
//          the resumed-from ancestor session when its descendant is live.
// See docs/specs/session-overcounting.md.

@Suite("Session over-counting — leaf filter (C2) + resume lineage (B1)")
struct SessionOvercountingTests {

    // MARK: - C2 · leafRows (drop wrapper/parent procs)

    private func row(_ pid: Int, ppid: Int) -> ProcessScanner.Row {
        ProcessScanner.Row(pid: pid, ppid: ppid, tty: nil, cpu: 0, command: "/x/claude")
    }

    @Test("leafRows drops a parent claude proc, keeps the leaf child")
    func leafDropsLauncherParent() {
        // 76505 (the disclaimer launcher) is the parent of 76506 (the real claude). 1275 is
        // the desktop app and isn't a claude row at all.
        let kept = ProcessScanner.leafRows([row(76505, ppid: 1275), row(76506, ppid: 76505)])
        #expect(kept.map(\.pid) == [76506])
    }

    @Test("leafRows keeps independent sessions (different ppid chains)")
    func leafKeepsIndependentSessions() {
        let kept = ProcessScanner.leafRows([row(6000, ppid: 500), row(6001, ppid: 501)])
        #expect(Set(kept.map(\.pid)) == [6000, 6001])
    }

    @Test("leafRows keeps only the deepest leaf of a chain")
    func leafKeepsDeepestLeaf() {
        let kept = ProcessScanner.leafRows([row(10, ppid: 1), row(11, ppid: 10), row(12, ppid: 11)])
        #expect(kept.map(\.pid) == [12])
    }

    // MARK: - B1 · parseResumedFrom

    @Test("parseResumedFrom reads --resume <id>/--resume=<id>, ignores --resume-session-at")
    func parsesResume() {
        #expect(ProcessScanner.parseResumedFrom("/x/claude --resume e8a02c8d --fork-session --resume-session-at 5e59288b") == "e8a02c8d")
        #expect(ProcessScanner.parseResumedFrom("/x/claude --resume=abc123 --foo") == "abc123")
        #expect(ProcessScanner.parseResumedFrom("/x/claude --model opus") == nil)
        #expect(ProcessScanner.parseResumedFrom("/x/claude --resume --model opus") == nil)   // no value
        #expect(ProcessScanner.parseResumedFrom("/x/claude --resume-session-at 5e59288b") == nil)   // not --resume
    }

    // MARK: - B1 · merge collapses the resume ancestor

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func sig(_ id: String, cwd: String, text: String, age: TimeInterval) -> TranscriptSignal {
        TranscriptSignal(sessionId: id, cwd: cwd, lastRole: "assistant", lastStopReason: "tool_use",
                         pendingToolUses: 1, lastText: text, lastActivity: now.addingTimeInterval(-age))
    }
    private func reg(_ pid: Int, _ id: String, cwd: String) -> RegistryEntry {
        RegistryEntry(pid: pid, sessionId: id, cwd: cwd, status: "busy", kind: "interactive", version: "2.1.170")
    }

    @Test("merge drops the resumed-from ancestor when its descendant is live → one row")
    func mergeCollapsesAncestor() {
        let cwd = "/Users/dev/Projects/app"
        // A live registered process for the forked session NEW, whose cmdline resumed OLD.
        let proc = ProcessRecord(pid: 76506, ppid: 1, tty: "ttys0", cwd: cwd, cpu: 1, resumedFrom: "OLD")
        let sessions = SessionMerger.merge(
            processes: [proc],
            registry: [reg(76506, "NEW", cwd: cwd)],
            transcripts: [sig("NEW", cwd: cwd, text: "current", age: 0),
                          sig("OLD", cwd: cwd, text: "ancestor", age: 600)],
            now: now
        )
        #expect(sessions.map(\.id) == ["NEW"])   // OLD collapsed away
    }

    @Test("merge keeps two genuinely distinct sessions — no over-collapse")
    func mergeKeepsDistinctSessions() {
        let cwd = "/Users/dev/Projects/app"
        let sessions = SessionMerger.merge(
            processes: [ProcessRecord(pid: 100, ppid: 1, tty: "ttys1", cwd: cwd, cpu: 1),
                        ProcessRecord(pid: 101, ppid: 1, tty: "ttys2", cwd: cwd, cpu: 1)],
            registry: [reg(100, "A", cwd: cwd), reg(101, "B", cwd: cwd)],
            transcripts: [sig("A", cwd: cwd, text: "a", age: 0), sig("B", cwd: cwd, text: "b", age: 0)],
            now: now
        )
        #expect(Set(sessions.map(\.id)) == ["A", "B"])
    }
}
