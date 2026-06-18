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
}
