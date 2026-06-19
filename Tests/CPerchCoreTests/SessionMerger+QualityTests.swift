import Testing
import Foundation
@testable import CPerchCore

// Uses swift-testing (`import Testing`), not XCTest — XCTest ships only with full
// Xcode, while Testing.framework is in the Command Line Tools.
//
// Track M (roster-and-merge-quality v0.2) — quality findings on the merge:
//   • L1  — distinguish "waiting on you" from "done" via `looksLikeAwaitingUser`.
//   • L2  — `displayName` prefers the AI title, basename as fallback.
//   • D4  — normalize cwd on both sides of the Pass-2 join (symlinks / trailing slash).
//   • D5  — registry tie-break on duplicate sessionId: live pid, else newest `startedAt`.
//   • D9  — alias seam: `canonicalSessionId` collapses an injected `cli↔local_` pair.
//
// These exercise the pure merge function and its new helpers in isolation. The
// factories in `SessionMergerTests` are `private` to that suite, so this file
// defines its own (intentionally local) synthetic-record factories. `now` is fixed
// so every freshness / threshold assertion is deterministic.

@Suite("SessionMerger — quality (L1 status, L2 name, D4 join, D5 tie-break, D9 alias)")
struct SessionMergerQualityTests {

    // Fixed clock so freshness-based status is deterministic across every case.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Local synthetic-record factories

    private func proc(pid: Int, tty: String? = "ttys000", cwd: String?,
                      cpu: Double = 0, start: Date? = nil) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: 1, tty: tty, cwd: cwd, cpu: cpu, startTime: start)
    }

    private func reg(pid: Int, sessionId: String, cwd: String, status: String? = nil,
                     kind: String? = "interactive", started: Date? = nil) -> RegistryEntry {
        RegistryEntry(pid: pid, sessionId: sessionId, cwd: cwd,
                      status: status, kind: kind, version: "2.1.170", startedAt: started)
    }

    private func sig(sessionId: String, cwd: String, lastRole: String? = "assistant",
                     stop: String? = nil, pending: Int = 0, text: String? = nil,
                     age: TimeInterval = 0, aiTitle: String? = nil) -> TranscriptSignal {
        TranscriptSignal(sessionId: sessionId, cwd: cwd, lastRole: lastRole,
                         lastStopReason: stop, pendingToolUses: pending, lastText: text,
                         lastActivity: now.addingTimeInterval(-age), aiTitle: aiTitle)
    }

    /// Merge one alive session (process pid == registry pid) and return its derived
    /// status. With `status: nil` this funnels through the transcript heuristic — the
    /// path L1 changes for the `end_turn`/`stop_sequence`/`max_tokens` arm.
    private func liveStatus(pid: Int, cwd: String, sig: TranscriptSignal) -> DerivedStatus? {
        SessionMerger.merge(
            processes: [proc(pid: pid, cwd: cwd)],
            registry: [reg(pid: pid, sessionId: sig.sessionId, cwd: cwd)],
            transcripts: [sig],
            now: now
        ).first?.status
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - L1 · waiting-vs-done
    // ─────────────────────────────────────────────────────────────────────────

    // AC-L1.1 — alive + end_turn whose lastText is a question → needsInput (the
    // assistant asked you something and parked; the ball is in your court).
    @Test("AC-L1.1 · alive + end_turn + \"Should I deploy to prod?\" → needsInput")
    func endTurnWithQuestionIsNeedsInput() {
        let cwd = "/Users/dev/Projects/api"
        let s = liveStatus(pid: 4242, cwd: cwd,
                           sig: sig(sessionId: "S-Q", cwd: cwd, stop: "end_turn",
                                    text: "Should I deploy to prod?", age: 1))
        #expect(s == .needsInput)
    }

    // AC-L1.2 — alive + end_turn whose lastText is a finished statement → concluded
    // (a completed task, no open question — must stay green, not nag).
    @Test("AC-L1.2 · alive + end_turn + \"All tests pass. Done.\" → concluded")
    func endTurnWithDoneTextIsConcluded() {
        let cwd = "/Users/dev/Projects/api"
        let s = liveStatus(pid: 4242, cwd: cwd,
                           sig: sig(sessionId: "S-DONE", cwd: cwd, stop: "end_turn",
                                    text: "All tests pass. Done.", age: 1))
        #expect(s == .concluded)
    }

    // AC-L1.3 — a dead session (no live pid) with question text is still concluded:
    // the `!alive` guard short-circuits before the heuristic, so we never nag a
    // session whose process is gone.
    @Test("AC-L1.3 · dead + question text → concluded (liveness gates first)")
    func deadSessionWithQuestionIsConcluded() {
        let cwd = "/Users/dev/Projects/api"
        let s = SessionMerger.merge(
            processes: [],   // pid absent → not alive
            registry: [reg(pid: 4242, sessionId: "S-DEADQ", cwd: cwd)],
            transcripts: [sig(sessionId: "S-DEADQ", cwd: cwd, stop: "end_turn",
                              text: "Should I deploy to prod?", age: 1)],
            now: now
        ).first?.status
        #expect(s == .concluded)
    }

    // AC-L1.4 — `looksLikeAwaitingUser` truth table. Biased to few false positives:
    // a trailing `?` or a clear permission/question phrase trips it; a finished
    // statement (even one with a `?` mid-sentence) must NOT.
    @Test("AC-L1.4 · looksLikeAwaitingUser truth table")
    func looksLikeAwaitingUserTruthTable() {
        // Positives — trailing question mark (with trailing whitespace tolerated).
        #expect(SessionMerger.looksLikeAwaitingUser("Should I deploy to prod?"))
        #expect(SessionMerger.looksLikeAwaitingUser("Ready to merge?  \n"))
        // Positives — curated permission/question phrases (case-insensitive).
        #expect(SessionMerger.looksLikeAwaitingUser("Let me know how you'd like to proceed."))
        #expect(SessionMerger.looksLikeAwaitingUser("Would you like me to continue."))
        #expect(SessionMerger.looksLikeAwaitingUser("Shall I run the migration now."))
        #expect(SessionMerger.looksLikeAwaitingUser("Do you want me to revert it."))
        #expect(SessionMerger.looksLikeAwaitingUser("Please confirm before I proceed."))
        #expect(SessionMerger.looksLikeAwaitingUser("Approve this change to continue."))
        #expect(SessionMerger.looksLikeAwaitingUser("Want me to push the branch."))

        // Negatives — a finished statement with a rhetorical `?` NOT at the end must
        // not trip (this is the key false-positive guard from AC-L1.4).
        #expect(!SessionMerger.looksLikeAwaitingUser("I checked whether the cache was stale? yes, and finished."))
        #expect(!SessionMerger.looksLikeAwaitingUser("All tests pass. Done."))
        #expect(!SessionMerger.looksLikeAwaitingUser("Refactored the router and committed."))
        // Negatives — WORD-BOUNDARY guards (integration-review catch): a curated phrase that
        // is only a substring of a longer word must NOT trip, else common closing statements
        // would nag. ("should investigate"/"should include" ⊅ "should i"; "confirmed" ⊅
        // "confirm"; "approved" ⊅ "approve".)
        #expect(!SessionMerger.looksLikeAwaitingUser("You should investigate the logs."))
        #expect(!SessionMerger.looksLikeAwaitingUser("We should include the header."))
        #expect(!SessionMerger.looksLikeAwaitingUser("I confirmed the tests pass."))
        #expect(!SessionMerger.looksLikeAwaitingUser("Changes approved and merged."))
        // Negatives — nil / empty / whitespace.
        #expect(!SessionMerger.looksLikeAwaitingUser(nil))
        #expect(!SessionMerger.looksLikeAwaitingUser(""))
        #expect(!SessionMerger.looksLikeAwaitingUser("   \n  "))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - L2 · displayName (AI title wins, basename fallback)
    // ─────────────────────────────────────────────────────────────────────────

    // AC-L2 (M's piece) — when the transcript carries an aiTitle, it becomes the
    // displayName; when it doesn't, the cwd basename is used.
    @Test("L2 · aiTitle wins over basename; nil aiTitle → basename")
    func displayNamePrefersAiTitleElseBasename() {
        let cwd = "/Users/dev/Projects/claude-toolbar-mac"

        let titled = SessionMerger.merge(
            processes: [proc(pid: 50, cwd: cwd)],
            registry: [reg(pid: 50, sessionId: "S-TITLED", cwd: cwd, status: "busy")],
            transcripts: [sig(sessionId: "S-TITLED", cwd: cwd, aiTitle: "Roster dedup work")],
            now: now
        ).first
        #expect(titled?.displayName == "Roster dedup work")   // AI title wins

        let untitled = SessionMerger.merge(
            processes: [proc(pid: 51, cwd: cwd)],
            registry: [reg(pid: 51, sessionId: "S-UNTITLED", cwd: cwd, status: "busy")],
            transcripts: [sig(sessionId: "S-UNTITLED", cwd: cwd, aiTitle: nil)],
            now: now
        ).first
        #expect(untitled?.displayName == "claude-toolbar-mac")   // basename fallback
    }

    // A registry-only session (no transcript ⇒ no aiTitle source) still gets the
    // basename — the fallback must not crash when sig is nil.
    @Test("L2 · no transcript → basename displayName")
    func displayNameBasenameWhenNoTranscript() {
        let cwd = "/Users/dev/Projects/web"
        let s = SessionMerger.merge(
            processes: [proc(pid: 52, cwd: cwd)],
            registry: [reg(pid: 52, sessionId: "S-NOSIG", cwd: cdwOrCwd(cwd), status: "busy")],
            transcripts: [],
            now: now
        ).first
        #expect(s?.displayName == "web")
    }

    // tiny indirection so a stray typo can't silently pass — keeps cwd literal honest
    private func cdwOrCwd(_ s: String) -> String { s }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - D4 · normalize the cwd join
    // ─────────────────────────────────────────────────────────────────────────

    // D4 uses `resolvingSymlinksInPath()`, which only resolves symlinks that exist on
    // disk — so these tests create a REAL temp directory and address it by both its
    // `/var/folders/...`-style canonical path and a synthetic `/tmp/<same>` spelling.
    // This exercises the genuine macOS symlink behavior the spec's AC-D4.1 targets
    // (`/tmp` → `/private/tmp`), rather than a path the resolver would leave untouched.

    /// Make a real, unique temp directory; returns its canonical path. Each test cleans
    /// up its own dir. Using a real dir is what lets symlink resolution actually fire.
    private func makeRealTempDir(_ label: String) -> String {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cperch-d4-\(label)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.path
    }

    /// The same directory addressed via the `/tmp` symlink instead of its canonical
    /// `/private/tmp` (or `/var/folders/...`) form. On macOS `/private/tmp/x` and
    /// `/var/folders/.../T/x` both live under `/private`, reachable as `/tmp/...` only
    /// when the canonical path starts with `/private/tmp`. To guarantee the symlink case,
    /// we anchor the temp dir under `/private/tmp` and build the `/tmp/...` twin.
    @Test("AC-D4.1 · /tmp/x vs /private/tmp/x joins via normalization")
    func symlinkedTmpPathsJoin() {
        // Anchor under /private/tmp so a /tmp twin resolves to the same inode.
        let name = "cperch-d4-join-\(UUID().uuidString)"
        let canonical = "/private/tmp/\(name)"
        let viaSymlink = "/tmp/\(name)"
        try? FileManager.default.createDirectory(atPath: canonical, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: canonical) }

        let sessions = SessionMerger.merge(
            processes: [proc(pid: 6000, tty: "ttys004", cwd: viaSymlink, cpu: 3.0)],
            registry: [],   // unregistered → Pass-2 cwd join is the only bridge
            transcripts: [sig(sessionId: "S-D4", cwd: canonical, lastRole: "user",
                              stop: "tool_use", pending: 1, text: "tests", age: 5)],
            now: now
        )
        #expect(sessions.count == 1)
        let s = try! #require(sessions.first)
        #expect(s.pid == 6000)            // bound despite /tmp vs /private/tmp spelling
        #expect(s.status == .running)     // alive → fresh pending tool
    }

    // AC-D4.2 — a trailing-slash variant must also join (normalization strips it).
    // Trailing-slash stripping is pure string work, so a real dir isn't required here.
    @Test("AC-D4.2 · trailing-slash variant joins")
    func trailingSlashPathsJoin() {
        let dir = makeRealTempDir("slash")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let procCwd = dir + "/"   // trailing slash
        let sigCwd  = dir         // none
        let sessions = SessionMerger.merge(
            processes: [proc(pid: 6010, tty: "ttys005", cwd: procCwd, cpu: 2.0)],
            registry: [],
            transcripts: [sig(sessionId: "S-D4S", cwd: sigCwd, lastRole: "user",
                              stop: "tool_use", pending: 1, text: "tests", age: 5)],
            now: now
        )
        let s = try! #require(sessions.first)
        #expect(s.pid == 6010)
        #expect(s.status == .running)
    }

    // AC-D4.3 — DISTINCT directories must NOT collide just because we normalize:
    // a process in one dir must not bind a transcript in a sibling dir → concluded.
    @Test("AC-D4.3 · distinct dirs do not collide")
    func distinctDirsDoNotCollide() {
        let dirA = makeRealTempDir("a")
        let dirB = makeRealTempDir("b")
        defer { try? FileManager.default.removeItem(atPath: dirA)
                try? FileManager.default.removeItem(atPath: dirB) }
        let sessions = SessionMerger.merge(
            processes: [proc(pid: 6020, tty: "ttys006", cwd: dirA, cpu: 1.0)],
            registry: [],
            transcripts: [sig(sessionId: "S-D4B", cwd: dirB, lastRole: "user",
                              stop: "tool_use", pending: 1, text: "tests", age: 5)],
            now: now
        )
        let s = try! #require(sessions.first)
        #expect(s.pid == nil)             // different dir → no bind
        #expect(s.status == .concluded)   // unbound transcript → concluded
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - D5 · registry tie-break on duplicate sessionId
    // ─────────────────────────────────────────────────────────────────────────

    // AC-D5.1 — two registry entries share a sessionId but have different pids/cwds;
    // ONE pid is live. The live entry must win (its cwd/kind are the ones used),
    // regardless of which sorts first lexically by filename.
    @Test("AC-D5.1 · duplicate sessionId → the live-pid entry wins")
    func duplicateSessionIdLivePidWins() {
        let liveCwd = "/Users/dev/Projects/live-one"
        let deadCwd = "/Users/dev/Projects/dead-one"
        // pid 100 is LIVE (a matching process exists); pid 200 is dead.
        let sessions = SessionMerger.merge(
            processes: [proc(pid: 100, tty: "ttys001", cwd: liveCwd)],
            registry: [
                reg(pid: 200, sessionId: "DUP", cwd: deadCwd, status: "idle",
                    started: now.addingTimeInterval(-1000)),
                reg(pid: 100, sessionId: "DUP", cwd: liveCwd, status: "busy",
                    started: now.addingTimeInterval(-2000)),   // older startedAt, but LIVE
            ],
            transcripts: [],
            now: now
        )
        #expect(sessions.count == 1)
        let s = try! #require(sessions.first)
        #expect(s.pid == 100)               // bound to the live entry's pid
        #expect(s.projectPath == liveCwd)   // the live entry's cwd is authoritative
        #expect(s.status == .running)       // the live entry's "busy" status used
    }

    // AC-D5.2 — neither pid is live → the entry with the NEWEST startedAt wins (not
    // lexical filename order). Proven via the resulting cwd.
    @Test("AC-D5.2 · duplicate sessionId, neither live → newest startedAt wins")
    func duplicateSessionIdNewestStartedAtWins() {
        let olderCwd = "/Users/dev/Projects/older"
        let newerCwd = "/Users/dev/Projects/newer"
        let sessions = SessionMerger.merge(
            processes: [],   // neither pid live
            registry: [
                reg(pid: 300, sessionId: "DUP2", cwd: olderCwd, status: "idle",
                    started: now.addingTimeInterval(-5000)),   // older
                reg(pid: 301, sessionId: "DUP2", cwd: newerCwd, status: "idle",
                    started: now.addingTimeInterval(-100)),    // newest → should win
            ],
            transcripts: [],
            now: now
        )
        #expect(sessions.count == 1)
        let s = try! #require(sessions.first)
        #expect(s.projectPath == newerCwd)   // newest startedAt entry's cwd
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - D9 · alias seam (canonicalSessionId)
    // ─────────────────────────────────────────────────────────────────────────

    // AC-D9.1 — an injected `cli → local_` alias collapses two ids that would
    // otherwise be two separate sessions into ONE. The registry entry (cli id) and
    // the transcript (local_ id) merge into a single Session keyed by the canonical id.
    @Test("AC-D9.1 · injected alias collapses two ids into one session")
    func injectedAliasCollapsesTwoIds() {
        let cwd = "/Users/dev/Projects/aliased"
        let cliId = "cli-abc"
        let localId = "local_abc"

        // Without aliases: two distinct sessions.
        let split = SessionMerger.merge(
            processes: [proc(pid: 900, tty: "ttys001", cwd: cwd)],
            registry: [reg(pid: 900, sessionId: cliId, cwd: cwd, status: "busy")],
            transcripts: [sig(sessionId: localId, cwd: cwd, text: "hi")],
            now: now
        )
        #expect(split.count == 2)   // sanity: distinct ids ⇒ two rows by default

        // With an alias mapping the cli id onto the local id, they collapse to one.
        let merged = SessionMerger.merge(
            processes: [proc(pid: 900, tty: "ttys001", cwd: cwd)],
            registry: [reg(pid: 900, sessionId: cliId, cwd: cwd, status: "busy")],
            transcripts: [sig(sessionId: localId, cwd: cwd, text: "hi")],
            now: now,
            aliases: [cliId: localId]
        )
        #expect(merged.count == 1)
        let s = try! #require(merged.first)
        #expect(s.id == localId)            // canonical id is the alias target
        #expect(s.latestMessage == "hi")    // transcript signal still attached
        #expect(s.status == .running)       // registry "busy" carried through the alias
    }

    // AC-D9.2 — empty aliases (the default) yield IDENTICAL output to not passing
    // the parameter at all: no regression for the present (no desktop source yet).
    @Test("AC-D9.2 · empty aliases ⇒ identical to default output")
    func emptyAliasesNoChange() {
        let cwd = "/Users/dev/Projects/api"
        let processes = [proc(pid: 910, tty: "ttys001", cwd: cwd)]
        let registry = [reg(pid: 910, sessionId: "S-NOALIAS", cwd: cwd, status: "busy")]
        let transcripts = [sig(sessionId: "S-NOALIAS", cwd: cwd, stop: "tool_use", text: "working")]

        let baseline = SessionMerger.merge(processes: processes, registry: registry,
                                           transcripts: transcripts, now: now)
        let withEmpty = SessionMerger.merge(processes: processes, registry: registry,
                                            transcripts: transcripts, now: now, aliases: [:])
        #expect(baseline == withEmpty)
    }

    // `canonicalSessionId` itself: maps when present, passes through when absent.
    @Test("D9 · canonicalSessionId maps when present, else identity")
    func canonicalSessionIdHelper() {
        #expect(SessionMerger.canonicalSessionId("cli-abc", aliases: ["cli-abc": "local_abc"]) == "local_abc")
        #expect(SessionMerger.canonicalSessionId("cli-abc", aliases: [:]) == "cli-abc")
        #expect(SessionMerger.canonicalSessionId("other", aliases: ["cli-abc": "local_abc"]) == "other")
    }
}
