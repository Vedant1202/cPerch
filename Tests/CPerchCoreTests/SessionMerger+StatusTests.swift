import Testing
import Foundation
@testable import CPerchCore

// Track C / finding D2 (DD-5): the transcript-heuristic path is the one that actually
// runs on the current Claude CLI, because real registry files OMIT `status`. With
// `status == nil`, `deriveStatus`' `busy`/`waiting`/`idle` switch never fires and every
// alive session falls through to the transcript heuristic (SessionMerger.swift, the
// `registryStatus == nil` branch). The existing `SessionMergerTests` always set a
// non-nil status, so that real path went uncovered. These are CHARACTERIZATION tests of
// EXISTING behavior — they pin the heuristic and the 120 s `stalledThreshold` boundary.
//
// Liveness is established the same way the merge binds it: a live ProcessRecord whose
// `pid` matches the RegistryEntry's `pid` (Pass 1 sets `pidForSession[entry.sessionId]`).
// `now` is fixed for deterministic freshness; per the spec, `startTime`/`startedAt` are
// left nil (so the D3 reuse guard, when present, trusts the bind on missing data).

@Suite("SessionMerger — status-absent transcript heuristic (D2)")
struct SessionMergerStatusTests {

    // Fixed clock so every freshness / threshold assertion is deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// `stalledThreshold` is a strict `>`: 120 s exactly is NOT stalled, 120 s + ε is.
    private let threshold = SessionMerger.stalledThreshold   // 120 s

    // MARK: - Local synthetic-record factories
    //
    // The factories in `SessionMergerTests` are `private` to that suite, so this file
    // defines its own. `startTime` / `startedAt` are intentionally omitted (left nil).

    private func proc(pid: Int, tty: String? = "ttys000", cwd: String?) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: 1, tty: tty, cwd: cwd, cpu: 0)
    }

    /// A registry entry mirroring the current CLI shape: `status` is nil.
    private func reg(pid: Int, sessionId: String, cwd: String,
                     kind: String? = "interactive") -> RegistryEntry {
        RegistryEntry(pid: pid, sessionId: sessionId, cwd: cwd,
                      status: nil, kind: kind, version: "2.1.170")
    }

    private func sig(sessionId: String, cwd: String, lastRole: String? = "assistant",
                     stop: String? = nil, pending: Int = 0, text: String? = nil,
                     age: TimeInterval) -> TranscriptSignal {
        TranscriptSignal(sessionId: sessionId, cwd: cwd, lastRole: lastRole,
                         lastStopReason: stop, pendingToolUses: pending, lastText: text,
                         lastActivity: now.addingTimeInterval(-age))
    }

    /// Merge one alive session (process pid == registry pid, status nil) and return its
    /// derived status. This funnels every case through the real `status: nil` heuristic.
    private func status(pid: Int, cwd: String, sig: TranscriptSignal) -> DerivedStatus? {
        SessionMerger.merge(
            processes: [proc(pid: pid, cwd: cwd)],
            registry: [reg(pid: pid, sessionId: sig.sessionId, cwd: cwd)],
            transcripts: [sig],
            now: now
        ).first?.status
    }

    // MARK: - AC-D2.1 · pending tool: fresh → running, stalled → needsInput

    @Test("alive + nil status + fresh pending tool → running")
    func freshPendingToolIsRunning() {
        let cwd = "/Users/dev/Projects/api"
        let s = status(pid: 4242, cwd: cwd,
                       sig: sig(sessionId: "S-PEND-FRESH", cwd: cwd, pending: 1, age: 5))
        // Quiet only 5 s (< 120 s) with a tool in flight → still working.
        #expect(s == .running)
    }

    @Test("alive + nil status + stalled pending tool → needsInput")
    func stalledPendingToolIsNeedsInput() {
        let cwd = "/Users/dev/Projects/api"
        let s = status(pid: 4242, cwd: cwd,
                       sig: sig(sessionId: "S-PEND-STALL", cwd: cwd, pending: 1, age: 300))
        // Quiet 300 s (> 120 s) with a pending tool → almost certainly blocked on the human.
        #expect(s == .needsInput)
    }

    // MARK: - AC-D2.2 · stop_reason end_turn / stop_sequence / max_tokens → concluded
    //
    // Each is concluded even while the process is alive (the turn finished cleanly), and
    // independent of freshness — proven here with a *fresh* (age 1 s) transcript so the
    // result can't be confused with the stalled path.

    @Test("alive + nil status + end_turn → concluded")
    func endTurnIsConcluded() {
        let cwd = "/Users/dev/Projects/api"
        let s = status(pid: 4242, cwd: cwd,
                       sig: sig(sessionId: "S-END", cwd: cwd, stop: "end_turn", age: 1))
        #expect(s == .concluded)
    }

    @Test("alive + nil status + stop_sequence → concluded")
    func stopSequenceIsConcluded() {
        let cwd = "/Users/dev/Projects/api"
        let s = status(pid: 4242, cwd: cwd,
                       sig: sig(sessionId: "S-STOPSEQ", cwd: cwd, stop: "stop_sequence", age: 1))
        #expect(s == .concluded)
    }

    @Test("alive + nil status + max_tokens → concluded")
    func maxTokensIsConcluded() {
        let cwd = "/Users/dev/Projects/api"
        let s = status(pid: 4242, cwd: cwd,
                       sig: sig(sessionId: "S-MAXTOK", cwd: cwd, stop: "max_tokens", age: 1))
        #expect(s == .concluded)
    }

    // MARK: - AC-D2.3 · last role `user` (no stop reason): fresh → running, stalled → needsInput
    //
    // This is the `default:` arm of the stop-reason switch: with no pending tool and no
    // recognized stop reason, a trailing `user` record means the model owes a reply.

    @Test("alive + nil status + last role user, fresh → running")
    func userRoleFreshIsRunning() {
        let cwd = "/Users/dev/Projects/api"
        let s = status(pid: 4242, cwd: cwd,
                       sig: sig(sessionId: "S-USER-FRESH", cwd: cwd, lastRole: "user", age: 5))
        #expect(s == .running)
    }

    @Test("alive + nil status + last role user, stalled → needsInput")
    func userRoleStalledIsNeedsInput() {
        let cwd = "/Users/dev/Projects/api"
        let s = status(pid: 4242, cwd: cwd,
                       sig: sig(sessionId: "S-USER-STALL", cwd: cwd, lastRole: "user", age: 300))
        #expect(s == .needsInput)
    }

    // A trailing `assistant` record with nothing pending and no recognized stop reason is
    // treated as done regardless of freshness — guards the `else` of the role ternary.
    @Test("alive + nil status + last role assistant, no pending → concluded")
    func assistantRoleNoPendingIsConcluded() {
        let cwd = "/Users/dev/Projects/api"
        let fresh = status(pid: 4242, cwd: cwd,
                           sig: sig(sessionId: "S-ASST-FRESH", cwd: cwd, lastRole: "assistant", age: 5))
        let stale = status(pid: 4242, cwd: cwd,
                           sig: sig(sessionId: "S-ASST-STALL", cwd: cwd, lastRole: "assistant", age: 300))
        #expect(fresh == .concluded)
        #expect(stale == .concluded)
    }

    // MARK: - AC-D2.4 · the 120 s threshold boundary (pending / tool_use case)
    //
    // `stalled` is `now.timeIntervalSince(lastActivity) > stalledThreshold`, a STRICT `>`.
    // So now−119 s (under) is running and now−121 s (over) flips to needsInput.

    @Test("threshold boundary: now-119s is running, now-121s is needsInput (pending tool)")
    func pendingToolThresholdBoundary() {
        let cwd = "/Users/dev/Projects/api"
        let under = status(pid: 4242, cwd: cwd,
                           sig: sig(sessionId: "S-BND-UNDER", cwd: cwd, pending: 1, age: threshold - 1))
        let over = status(pid: 4242, cwd: cwd,
                          sig: sig(sessionId: "S-BND-OVER", cwd: cwd, pending: 1, age: threshold + 1))
        #expect(under == .running)      // 119 s quiet → not yet stalled
        #expect(over == .needsInput)    // 121 s quiet → stalled
    }

    // Same boundary exercised via the `lastStopReason == "tool_use"` arm (no pending count),
    // to pin that the tool_use branch shares the identical 120 s threshold semantics.
    @Test("threshold boundary: now-119s is running, now-121s is needsInput (tool_use stop)")
    func toolUseStopThresholdBoundary() {
        let cwd = "/Users/dev/Projects/api"
        let under = status(pid: 4242, cwd: cwd,
                           sig: sig(sessionId: "S-TU-UNDER", cwd: cwd, stop: "tool_use", age: threshold - 1))
        let over = status(pid: 4242, cwd: cwd,
                          sig: sig(sessionId: "S-TU-OVER", cwd: cwd, stop: "tool_use", age: threshold + 1))
        #expect(under == .running)
        #expect(over == .needsInput)
    }

    // Exact boundary: at now − 120 s the strict `>` is false, so the session is NOT yet
    // stalled (still running). Pins the off-by-one direction of the comparison.
    @Test("threshold boundary: now-120s exactly is still running (strict >)")
    func exactThresholdIsNotStalled() {
        let cwd = "/Users/dev/Projects/api"
        let exact = status(pid: 4242, cwd: cwd,
                           sig: sig(sessionId: "S-BND-EXACT", cwd: cwd, pending: 1, age: threshold))
        #expect(exact == .running)
    }

    // MARK: - Liveness precondition: nil status alone never invents a status when dead.
    //
    // Anchors that these cases reach the heuristic *because* the session is alive: drop the
    // matching process and the same nil-status + pending-tool transcript is concluded
    // (the `!alive` guard short-circuits before the heuristic).
    @Test("nil status + pending tool but NO live process → concluded (heuristic not reached)")
    func deadSessionShortCircuitsToConcluded() {
        let cwd = "/Users/dev/Projects/api"
        let s = SessionMerger.merge(
            processes: [],   // pid 4242 absent → not alive
            registry: [reg(pid: 4242, sessionId: "S-DEAD", cwd: cwd)],
            transcripts: [sig(sessionId: "S-DEAD", cwd: cwd, pending: 1, age: 5)],
            now: now
        ).first?.status
        #expect(s == .concluded)
    }
}
