import Testing
import Foundation
@testable import CPerchCore

// Uses swift-testing (`import Testing`), not XCTest — XCTest ships only with full
// Xcode, while Testing.framework is in the Command Line Tools.
//
// SessionMerger (P1-G) is a pure function: it folds the three frozen source-record
// types into the unified `[Session]` the rest of cPerch consumes. These tests build
// synthetic records by hand (no FS, no fixtures needed) so the merge logic — the
// dedup spine, the pid→sessionId bridge, the cwd fallback, liveness, and status
// resolution — is exercised in isolation.

@Suite("SessionMerger — dedup, bridge, status resolution")
struct SessionMergerTests {

    // Fixed clock so freshness-based status (the transcript fallback) is deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func proc(pid: Int, tty: String? = nil, cwd: String?, cpu: Double = 0) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: 1, tty: tty, cwd: cwd, cpu: cpu)
    }

    private func reg(pid: Int, sessionId: String, cwd: String,
                     status: String?, kind: String? = "interactive") -> RegistryEntry {
        RegistryEntry(pid: pid, sessionId: sessionId, cwd: cwd,
                      status: status, kind: kind, version: "1.0.0")
    }

    private func sig(sessionId: String, cwd: String, lastRole: String? = "assistant",
                     stop: String? = nil, pending: Int = 0, text: String? = nil,
                     age: TimeInterval = 0) -> TranscriptSignal {
        TranscriptSignal(sessionId: sessionId, cwd: cwd, lastRole: lastRole,
                         lastStopReason: stop, pendingToolUses: pending, lastText: text,
                         lastActivity: now.addingTimeInterval(-age))
    }

    // MARK: - 1) Full three-source merge into one Session

    @Test func mergesThreeSourcesIntoOneSession() {
        let cwd = "/Users/dev/Projects/api"
        let sessions = SessionMerger.merge(
            processes: [proc(pid: 4242, tty: "ttys004", cwd: cwd, cpu: 12.0)],
            registry: [reg(pid: 4242, sessionId: "S-API", cwd: cwd, status: "busy")],
            transcripts: [sig(sessionId: "S-API", cwd: cwd, stop: "tool_use",
                              text: "Refactoring the router…")],
            now: now
        )

        #expect(sessions.count == 1)
        let s = try! #require(sessions.first)
        #expect(s.id == "S-API")
        #expect(s.pid == 4242)                                  // bridged via registry
        #expect(s.projectPath == cwd)
        #expect(s.displayName == "api")                         // cwd basename
        #expect(s.status == .running)                           // registry busy → running
        #expect(s.source == .cli)                               // interactive + tty
        #expect(s.latestMessage == "Refactoring the router…")   // from transcript
        #expect(s.host == .terminal(app: "Terminal", tty: "ttys004"))
        #expect(s.blockedSince == nil)                          // store sets this over time
        #expect(s.lastActivity == now)
    }

    // MARK: - 2) Registry pid NOT among processes → concluded

    @Test func staleRegistryEntryWithDeadPidIsConcluded() {
        let cwd = "/Users/dev/Projects/web"
        let sessions = SessionMerger.merge(
            processes: [],                                       // pid 99 is gone
            registry: [reg(pid: 99, sessionId: "S-DEAD", cwd: cwd, status: "busy")],
            transcripts: [sig(sessionId: "S-DEAD", cwd: cwd, stop: "tool_use", text: "half-done")],
            now: now
        )

        #expect(sessions.count == 1)
        let s = try! #require(sessions.first)
        #expect(s.id == "S-DEAD")
        #expect(s.status == .concluded)        // not alive overrides registry "busy"
        #expect(s.pid == nil)                  // no live process
        #expect(s.latestMessage == "half-done")
        // No tty, interactive kind → desktop host fallback.
        #expect(s.host == .desktop(bundleID: "com.anthropic.claudefordesktop"))
    }

    // MARK: - 3) Unregistered process matched to a transcript via cwd

    @Test func unregisteredProcessMatchesTranscriptByCwd() {
        let cwd = "/Users/dev/Projects/cli-only"
        // No registry entry for pid 7000; it must join its transcript by cwd.
        let sessions = SessionMerger.merge(
            processes: [proc(pid: 7000, tty: "ttys009", cwd: cwd, cpu: 3.0)],
            registry: [],
            transcripts: [sig(sessionId: "S-CWD", cwd: cwd, lastRole: "user",
                              stop: "tool_use", pending: 1, text: "running tests", age: 5)],
            now: now
        )

        #expect(sessions.count == 1)
        let s = try! #require(sessions.first)
        #expect(s.id == "S-CWD")               // keyed by the transcript's sessionId
        #expect(s.pid == 7000)                 // process bridged via cwd
        #expect(s.status == .running)          // no registry status → fresh pending tool = running
        #expect(s.host == .terminal(app: "Terminal", tty: "ttys009"))
        #expect(s.latestMessage == "running tests")
    }

    // MARK: - 4) Two sessions sharing a cwd (collision) — no crash, both survive

    @Test func cwdCollisionIsHandledWithoutCrashing() {
        let cwd = "/Users/dev/Projects/shared"
        // Two transcripts in the same directory; one live unregistered process.
        let sessions = SessionMerger.merge(
            processes: [proc(pid: 8001, tty: "ttys010", cwd: cwd, cpu: 1.0)],
            registry: [],
            transcripts: [
                sig(sessionId: "S-OLD", cwd: cwd, stop: "end_turn", text: "older", age: 600),
                sig(sessionId: "S-NEW", cwd: cwd, lastRole: "user", stop: "tool_use",
                    pending: 1, text: "newer", age: 2),
            ],
            now: now
        )

        // Both transcripts become sessions, keyed distinctly by sessionId — no collapse,
        // no crash. The live process attaches to exactly one (the most-recent).
        #expect(sessions.count == 2)
        let ids = Set(sessions.map(\.id))
        #expect(ids == ["S-OLD", "S-NEW"])

        let new = try! #require(sessions.first { $0.id == "S-NEW" })
        let old = try! #require(sessions.first { $0.id == "S-OLD" })
        #expect(new.pid == 8001)               // process bound to most-recent activity
        #expect(old.pid == nil)                // the stale one gets no live process
        #expect(old.status == .concluded)      // dead + end_turn → concluded
    }

    // MARK: - Status-resolution coverage (registry > transcript), per SPEC §3

    @Test func waitingRegistryStatusIsNeedsInput() {
        let cwd = "/Users/dev/p"
        let s = SessionMerger.merge(
            processes: [proc(pid: 11, tty: "ttys001", cwd: cwd)],
            registry: [reg(pid: 11, sessionId: "W", cwd: cwd, status: "waiting")],
            transcripts: [sig(sessionId: "W", cwd: cwd)],
            now: now
        ).first
        #expect(s?.status == .needsInput)
    }

    @Test func idleWithPendingToolIsNeedsInputElseConcluded() {
        let cwd = "/Users/dev/p"
        let needs = SessionMerger.merge(
            processes: [proc(pid: 12, cwd: cwd)],
            registry: [reg(pid: 12, sessionId: "I1", cwd: cwd, status: "idle")],
            transcripts: [sig(sessionId: "I1", cwd: cwd, pending: 1)],
            now: now
        ).first
        #expect(needs?.status == .needsInput)   // idle but parked mid-tool

        let done = SessionMerger.merge(
            processes: [proc(pid: 13, cwd: cwd)],
            registry: [reg(pid: 13, sessionId: "I2", cwd: cwd, status: "idle")],
            transcripts: [sig(sessionId: "I2", cwd: cwd, pending: 0)],
            now: now
        ).first
        #expect(done?.status == .concluded)     // idle, nothing pending
    }

    @Test func nilStatusFallsBackToTranscriptHeuristic() {
        let cwd = "/Users/dev/p"
        // Stalled pending tool (older than 120s) with no registry status → needs-input.
        let stalled = SessionMerger.merge(
            processes: [proc(pid: 14, tty: "ttys002", cwd: cwd)],
            registry: [reg(pid: 14, sessionId: "ST", cwd: cwd, status: nil)],
            transcripts: [sig(sessionId: "ST", cwd: cwd, stop: "tool_use", pending: 1, age: 300)],
            now: now
        ).first
        #expect(stalled?.status == .needsInput)

        // end_turn with no registry status → concluded even while alive.
        let ended = SessionMerger.merge(
            processes: [proc(pid: 15, tty: "ttys003", cwd: cwd)],
            registry: [reg(pid: 15, sessionId: "ET", cwd: cwd, status: nil)],
            transcripts: [sig(sessionId: "ET", cwd: cwd, stop: "end_turn")],
            now: now
        ).first
        #expect(ended?.status == .concluded)
    }

    // MARK: - Sort order: needs-you-first, then lastActivity desc

    @Test func sortsNeedsInputFirstThenRunningThenConcludedByRecency() {
        let sessions = SessionMerger.merge(
            processes: [
                proc(pid: 21, cwd: "/a"), proc(pid: 22, cwd: "/b"), proc(pid: 23, cwd: "/c"),
            ],
            registry: [
                reg(pid: 21, sessionId: "run", cwd: "/a", status: "busy"),
                reg(pid: 22, sessionId: "need", cwd: "/b", status: "waiting"),
                reg(pid: 23, sessionId: "conc", cwd: "/c", status: "idle"),
            ],
            transcripts: [
                sig(sessionId: "run", cwd: "/a", age: 10),
                sig(sessionId: "need", cwd: "/b", age: 50),
                sig(sessionId: "conc", cwd: "/c", age: 1),
            ],
            now: now
        )
        #expect(sessions.map(\.id) == ["need", "run", "conc"])
    }

    @Test func tiesWithinStatusBreakByLastActivityDesc() {
        let sessions = SessionMerger.merge(
            processes: [proc(pid: 31, tty: "ttys001", cwd: "/x"),
                        proc(pid: 32, tty: "ttys002", cwd: "/y")],
            registry: [
                reg(pid: 31, sessionId: "older", cwd: "/x", status: "waiting"),
                reg(pid: 32, sessionId: "newer", cwd: "/y", status: "waiting"),
            ],
            transcripts: [
                sig(sessionId: "older", cwd: "/x", age: 100),
                sig(sessionId: "newer", cwd: "/y", age: 5),
            ],
            now: now
        )
        // Same status (needsInput) → most-recent activity first.
        #expect(sessions.map(\.id) == ["newer", "older"])
    }
}
