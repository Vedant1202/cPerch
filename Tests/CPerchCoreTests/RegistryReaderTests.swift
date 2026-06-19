import Testing
import Foundation
@testable import CPerchCore

// Uses swift-testing (`import Testing`), not XCTest — XCTest ships only with full
// Xcode, while Testing.framework is in the Command Line Tools.
//
// Fixtures live in Tests/fixtures/registry-dir/ next to this source tree. SPM doesn't
// bundle test resources (Package.swift declares none and is frozen), so we locate them
// from `#filePath` rather than `Bundle.module`. The directory holds:
//   4242.json — copy of sample-registry.json (status: "waiting")
//   5151.json — desktop case with NO `status` field
//   9999.json — malformed (non-JSON), must be skipped
@Suite("RegistryReader")
struct RegistryReaderTests {

    /// Tests/fixtures/registry-dir/, resolved from this file's path at compile time.
    private static func fixtureDir(_ file: String = #filePath) -> URL {
        URL(fileURLWithPath: file)            // …/Tests/CPerchCoreTests/RegistryReaderTests.swift
            .deletingLastPathComponent()       // …/Tests/CPerchCoreTests
            .deletingLastPathComponent()       // …/Tests
            .appendingPathComponent("fixtures/registry-dir", isDirectory: true)
    }

    private func read() -> [RegistryEntry] {
        RegistryReader(directory: Self.fixtureDir()).read()
    }

    @Test("the waiting entry parses with every field")
    func parsesWaitingEntry() {
        let entries = read()
        let waiting = entries.first { $0.pid == 4242 }
        #expect(waiting != nil)
        #expect(waiting?.sessionId == "00000000-0000-4000-8000-000000000001")
        #expect(waiting?.cwd == "/Users/USER/Projects/example")
        #expect(waiting?.status == "waiting")
        #expect(waiting?.kind == "interactive")
        #expect(waiting?.version == "2.1.181")
        #expect(waiting?.entrypoint == "cli")   // v0.3: Terminal signal
    }

    @Test("the no-status desktop entry parses with status == nil")
    func parsesNoStatusEntry() {
        let entries = read()
        let desktop = entries.first { $0.pid == 5151 }
        #expect(desktop != nil)
        #expect(desktop?.sessionId == "00000000-0000-4000-8000-000000000002")
        #expect(desktop?.cwd == "/Users/USER/Projects/desktop-app")
        #expect(desktop?.status == nil)   // older Claude omits status — tolerated
        #expect(desktop?.kind == "interactive")
        #expect(desktop?.version == "1.4.0")
        #expect(desktop?.entrypoint == "claude-desktop")   // v0.3: Claude-app signal
    }

    @Test("a malformed file is skipped, not fatal")
    func skipsMalformedFile() {
        let entries = read()
        // Both valid entries survive; the malformed 9999.json is silently dropped.
        #expect(entries.count == 2)
        #expect(entries.contains { $0.pid == 4242 })
        #expect(entries.contains { $0.pid == 5151 })
        #expect(!entries.contains { $0.pid == 9999 })
    }

    @Test("a missing directory yields an empty list, not a crash")
    func missingDirectoryIsEmpty() {
        let bogus = Self.fixtureDir().appendingPathComponent("does-not-exist", isDirectory: true)
        #expect(RegistryReader(directory: bogus).read().isEmpty)
    }

    // MARK: - D3 · startedAt decode (epoch ms → Date) — AC-D3.4

    @Test("startedAt (epoch ms) decodes to the expected instant within 1s")
    func decodesStartedAtEpochMillis() {
        // 4242.json carries "startedAt": 1781750000000 (ms) → 1781750000 s.
        let entry = try! #require(read().first { $0.pid == 4242 })
        let startedAt = try! #require(entry.startedAt)
        let expected = Date(timeIntervalSince1970: 1_781_750_000)
        #expect(abs(startedAt.timeIntervalSince(expected)) < 1.0)
    }

    @Test("an entry with no startedAt key decodes to startedAt == nil, no throw")
    func absentStartedAtIsNil() throws {
        // A real-shaped file that simply omits `startedAt` (older CLI / partial write).
        // Written to a throwaway dir so registry-dir/ (count == 2 above) is untouched.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cperch-d3-nostart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let json = """
        {"pid":7777,"sessionId":"00000000-0000-4000-8000-000000007777",\
        "cwd":"/Users/USER/Projects/nostart","kind":"interactive","version":"2.1.181"}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("7777.json"))

        let entry = try #require(RegistryReader(directory: dir).read().first { $0.pid == 7777 })
        #expect(entry.startedAt == nil)
    }
}
