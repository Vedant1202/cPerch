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
}
