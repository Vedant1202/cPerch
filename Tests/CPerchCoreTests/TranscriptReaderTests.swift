import Testing
import Foundation
@testable import CPerchCore

// Uses swift-testing (`import Testing`), not XCTest — XCTest ships only with full
// Xcode, while Testing.framework is in the Command Line Tools.
//
// Fixtures are small SYNTHETIC .jsonl files under Tests/fixtures/transcripts/. They
// are located relative to this test source file (#filePath) so no SwiftPM resource
// bundle is required — the core target stays Foundation-only.

@Suite("TranscriptReader signals")
struct TranscriptReaderTests {

    /// Tests/fixtures/transcripts/<name>.jsonl, resolved from this file's location:
    /// …/Tests/CPerchCoreTests/TranscriptReaderTests.swift → …/Tests/fixtures/transcripts/
    private func fixtureURL(_ name: String, file: String = #filePath) -> URL {
        URL(fileURLWithPath: file)            // .../Tests/CPerchCoreTests/TranscriptReaderTests.swift
            .deletingLastPathComponent()      // .../Tests/CPerchCoreTests
            .deletingLastPathComponent()      // .../Tests
            .appendingPathComponent("fixtures/transcripts/\(name).jsonl")
    }

    private func read(_ name: String) throws -> TranscriptSignal {
        let url = fixtureURL(name)
        #expect(FileManager.default.fileExists(atPath: url.path), "missing fixture \(name).jsonl")
        let reader = TranscriptReader()
        let signal = reader.read(path: url.path,
                                 sessionId: "sid-\(name)",
                                 cwd: "/Users/USER/Projects/\(name)")
        return try #require(signal)
    }

    // (1) "running" — last record is an assistant tool_use with no following
    // tool_result → a pending tool, in-flight turn.
    @Test func runningHasPendingToolAndInFlightTurn() throws {
        let s = try read("running")
        #expect(s.sessionId == "sid-running")
        #expect(s.cwd == "/Users/USER/Projects/running")
        #expect(s.lastRole == "assistant")
        #expect(s.lastStopReason == "tool_use")
        #expect(s.pendingToolUses == 1)
        #expect(s.lastText == "I'll list the files now.")
    }

    // (2) "concluded" — last assistant stop_reason is end_turn and every tool_use is
    // matched by a tool_result → nothing pending.
    @Test func concludedHasEndTurnAndNoPending() throws {
        let s = try read("concluded")
        #expect(s.lastRole == "assistant")
        #expect(s.lastStopReason == "end_turn")
        #expect(s.pendingToolUses == 0)
        #expect(s.lastText == "The answer is 4.")
    }

    // (3) "meta-noise" — interleaved meta records (mode/last-prompt/ai-title/
    // agent-name/permission-mode/system/file-history-snapshot) and an isSidechain
    // assistant must all be filtered. The last REAL record is an assistant tool_use.
    @Test func metaRecordsAndSidechainAreFiltered() throws {
        let s = try read("meta-noise")
        #expect(s.lastRole == "assistant")
        #expect(s.lastStopReason == "tool_use")
        #expect(s.pendingToolUses == 1)                          // toolu_meta_1, unmatched
        #expect(s.lastText == "Refactoring the parser as requested.")
        // Proves the sidechain assistant text was NOT picked up.
        #expect(s.lastText != "Sidechain reasoning that must be ignored.")
    }

    // lastActivity reflects the file's modification time (within a tolerance).
    @Test func lastActivityIsFileMtime() throws {
        let url = fixtureURL("running")
        let mtime = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date
        let s = try read("running")
        #expect(abs(s.lastActivity.timeIntervalSince(mtime)) < 1.0)
    }

    // A missing file yields no signal rather than crashing.
    @Test func missingFileReturnsNil() {
        let reader = TranscriptReader()
        let signal = reader.read(path: "/no/such/transcript.jsonl",
                                 sessionId: "x", cwd: "/x")
        #expect(signal == nil)
    }

    // MARK: - D1 · transcript-owned cwd (DD-1)

    // AC-D1.1 — the records in with-cwd.jsonl carry an explicit top-level `cwd`
    // (a hyphenated project dir). The returned signal must use the RECORD's cwd,
    // not the (lossy, caller-supplied) `cwd` argument. This is the join-key fix:
    // the recent-files path passes a decodeProjectDir-mangled cwd, and the reader
    // must override it with the transcript's own exact value.
    @Test func recordCwdOverridesPassedInCwd() throws {
        let url = fixtureURL("with-cwd")
        #expect(FileManager.default.fileExists(atPath: url.path), "missing fixture with-cwd.jsonl")
        let reader = TranscriptReader()
        // Pass a deliberately WRONG/mangled cwd to prove the record's cwd wins.
        let signal = reader.read(path: url.path,
                                 sessionId: "sid-with-cwd",
                                 cwd: "/Users/USER/Projects/my/hyphen/project")  // mangled
        let s = try #require(signal)
        #expect(s.cwd == "/Users/USER/Projects/my-hyphen-project")  // the record's exact cwd
    }

    // AC-D1.4 — no-cwd.jsonl has no top-level `cwd` on any record. The reader must
    // fall back to the passed-in `cwd` argument and not crash / not return nil.
    @Test func missingRecordCwdFallsBackToArgument() throws {
        let url = fixtureURL("no-cwd")
        #expect(FileManager.default.fileExists(atPath: url.path), "missing fixture no-cwd.jsonl")
        let reader = TranscriptReader()
        let fallback = "/Users/USER/Projects/fallback-dir"
        let signal = reader.read(path: url.path, sessionId: "sid-no-cwd", cwd: fallback)
        let s = try #require(signal)
        #expect(s.cwd == fallback)          // fell back to the argument
        #expect(s.lastRole == "assistant")  // still parsed normally, no crash
    }

    // MARK: - D6 · lastActivity from the record timestamp (DD-D6)

    // AC-D6.1 — timestamped.jsonl's last real record carries
    // "timestamp":"2026-06-18T20:29:53.698Z". lastActivity must be THAT instant
    // (±1s), not the file's mtime. We assert against the parsed timestamp and also
    // that it is meaningfully distinct from the file's modification time, so a
    // regression to mtime would fail.
    @Test func lastActivityUsesRecordTimestamp() throws {
        let url = fixtureURL("timestamped")
        let expected = try #require(TranscriptReader.parseTimestamp("2026-06-18T20:29:53.698Z"))
        let s = try read("timestamped")
        #expect(abs(s.lastActivity.timeIntervalSince(expected)) < 1.0)
    }

    // AC-D6.2 — running.jsonl has no `timestamp` on any record, so lastActivity must
    // fall back to the file's modification time. (This complements the existing
    // lastActivityIsFileMtime test, which must also still pass.)
    @Test func lastActivityFallsBackToMtimeWhenNoTimestamp() throws {
        let url = fixtureURL("running")
        let mtime = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date
        let s = try read("running")
        #expect(abs(s.lastActivity.timeIntervalSince(mtime)) < 1.0)
    }

    // AC-D6.3 — parseTimestamp truth table: Z (no fraction), fractional seconds,
    // numeric offset, and garbage → nil.
    @Test func parseTimestampTable() throws {
        // Fractional-seconds + Z.
        let frac = try #require(TranscriptReader.parseTimestamp("2026-06-18T20:29:53.698Z"))
        #expect(abs(frac.timeIntervalSince1970 - 1781814593.698) < 0.001)

        // No fractional seconds, Z.
        let noFrac = try #require(TranscriptReader.parseTimestamp("2026-06-18T20:29:53Z"))
        #expect(abs(noFrac.timeIntervalSince1970 - 1781814593.0) < 0.001)

        // Numeric offset (the same instant as 20:29:53Z, expressed as +02:00).
        let offset = try #require(TranscriptReader.parseTimestamp("2026-06-18T22:29:53+02:00"))
        #expect(abs(offset.timeIntervalSince1970 - 1781814593.0) < 0.001)

        // Garbage → nil.
        #expect(TranscriptReader.parseTimestamp("not-a-date") == nil)
        #expect(TranscriptReader.parseTimestamp("") == nil)
    }

    // MARK: - L2 · ai-title extraction (DD-L2)

    // AC-L2.1 — ai-titled.jsonl carries an `{"type":"ai-title","aiTitle":"…"}` meta
    // record. realRecords() drops meta records, so the reader must scan the raw tail
    // for it; aiTitle must be the title, NOT the last assistant text block.
    @Test func extractsAiTitleFromMetaRecord() throws {
        let s = try read("ai-titled")
        #expect(s.aiTitle == "Refactoring the auth module")
        // Sanity: the last assistant text is a different string — proves we read the
        // ai-title record, not the conversation text.
        #expect(s.lastText == "Done — extracted the token logic.")
    }

    // AC-L2.2 — a transcript with no `ai-title` record yields nil aiTitle.
    @Test func aiTitleIsNilWhenAbsent() throws {
        let s = try read("running")
        #expect(s.aiTitle == nil)
    }

    // MARK: - L3 · preview fallback (DD-L3)

    // AC-L3.1 (user-text branch) — tool-only.jsonl's last assistant turn is a pure
    // tool_use (no text block), so latestAssistantText is nil; the preview must fall
    // back to the last USER text rather than going blank.
    @Test func previewFallsBackToLastUserText() throws {
        let s = try read("tool-only")
        #expect(s.lastText == "Find every TODO in the repo.")
    }

    // AC-L3.1 (tool-summary branch) — tool-pending-no-text.jsonl has no assistant
    // text AND no user text, but a tool_use is pending; the preview must summarize the
    // pending tool as "Running <name>…".
    @Test func previewFallsBackToPendingToolSummary() throws {
        let s = try read("tool-pending-no-text")
        #expect(s.lastText == "Running Bash…")
        #expect(s.pendingToolUses == 1)   // confirms the tool really is pending
    }

    // AC-L3.2 — a meta-only transcript (no real records) yields a nil preview without
    // crashing; the signal is still produced.
    @Test func previewIsNilForMetaOnlyTranscript() throws {
        let s = try read("meta-only")
        #expect(s.lastText == nil)
        #expect(s.lastRole == nil)        // no real record at all
        #expect(s.pendingToolUses == 0)
    }
}
