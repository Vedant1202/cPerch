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
}
