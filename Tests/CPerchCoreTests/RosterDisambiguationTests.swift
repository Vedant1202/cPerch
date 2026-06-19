import Testing
import Foundation
@testable import CPerchCore

// Uses swift-testing (`import Testing`), not XCTest — XCTest ships only with full
// Xcode, while Testing.framework is in the Command Line Tools. Keeps us Xcode-free.
//
// Track U / finding L2 (DD-L2): two sessions in the same project render IDENTICAL
// `displayName`s (cwd basename or AI title). The PURE helper computes a muted
// relative-time secondary label per colliding session so the rows are tellable apart;
// uniquely-named sessions get no entry. The view consumes this map verbatim, so all the
// testable logic lives here (AC-L2.3). `now` is fixed for deterministic relative times.

@Suite("RosterDisambiguation — collision labels (L2)")
struct RosterDisambiguationTests {

    // Fixed clock so every relative-time assertion is deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Minimal session factory — only `id`, `displayName`, and `lastActivity` matter to
    /// the helper; the rest are filler.
    private func session(id: String, name: String, ago seconds: TimeInterval) -> Session {
        Session(id: id, projectPath: "/x", displayName: name, source: .cli,
                status: .concluded, latestMessage: nil,
                lastActivity: now.addingTimeInterval(-seconds), blockedSince: nil,
                pid: nil, host: .unknown)
    }

    // MARK: - AC-L2.3 — colliding names get distinct labels

    @Test func collidingNamesBothLabeledDistinctly() {
        let sessions = [
            session(id: "aaaa-1111", name: "claude-toolbar-mac", ago: 120),  // 2m ago
            session(id: "bbbb-2222", name: "claude-toolbar-mac", ago: 3600), // 1h ago
        ]
        let labels = RosterDisambiguation.labels(for: sessions, now: now)

        // Both colliding rows get a label …
        #expect(labels["aaaa-1111"] != nil)
        #expect(labels["bbbb-2222"] != nil)
        // … and the labels differ so the rows are tellable apart.
        #expect(labels["aaaa-1111"] != labels["bbbb-2222"])
    }

    // MARK: - AC-L2.3 — uniquely-named sessions are not in the result

    @Test func uniqueNameGetsNoLabel() {
        let sessions = [
            session(id: "aaaa-1111", name: "alpha", ago: 60),
            session(id: "bbbb-2222", name: "beta", ago: 60),
        ]
        let labels = RosterDisambiguation.labels(for: sessions, now: now)
        #expect(labels.isEmpty)
    }

    /// A name shared by ≥2 sessions collides; a third, unique name in the same list does not.
    @Test func onlyCollidingNamesAreLabeled() {
        let sessions = [
            session(id: "aaaa-1111", name: "shared", ago: 30),
            session(id: "bbbb-2222", name: "shared", ago: 600),
            session(id: "cccc-3333", name: "solo", ago: 30),
        ]
        let labels = RosterDisambiguation.labels(for: sessions, now: now)
        #expect(labels["aaaa-1111"] != nil)
        #expect(labels["bbbb-2222"] != nil)
        #expect(labels["cccc-3333"] == nil)   // unique → no entry
        #expect(labels.count == 2)
    }

    // MARK: - AC-L2.3 — identical-time tiebreak still yields different labels

    @Test func identicalRelativeTimesAreTieBroken() {
        // Same name AND same lastActivity → identical relative-time strings; the helper
        // must append a short id-based disambiguator so the labels still differ.
        let sessions = [
            session(id: "aaaa-1111", name: "claude-toolbar-mac", ago: 120),
            session(id: "bbbb-2222", name: "claude-toolbar-mac", ago: 120),
        ]
        let labels = RosterDisambiguation.labels(for: sessions, now: now)

        let a = labels["aaaa-1111"]
        let b = labels["bbbb-2222"]
        #expect(a != nil)
        #expect(b != nil)
        #expect(a != b)                       // tiebreak applied
        // The disambiguator is drawn from the id prefix, so each label carries its own.
        #expect(a?.contains("aaaa") == true)
        #expect(b?.contains("bbbb") == true)
    }

    // MARK: - relative-time formatting

    @Test func relativeTimeFormats() {
        let sessions = [
            session(id: "now0", name: "dup", ago: 10),    // < 1m → "just now"
            session(id: "min2", name: "dup", ago: 120),   // 2m ago
            session(id: "hr1x", name: "dup", ago: 3600),  // 1h ago
            session(id: "day2", name: "dup", ago: 2 * 86_400), // 2d ago
        ]
        let labels = RosterDisambiguation.labels(for: sessions, now: now)
        #expect(labels["now0"] == "just now")
        #expect(labels["min2"] == "2m ago")
        #expect(labels["hr1x"] == "1h ago")
        #expect(labels["day2"] == "2d ago")
    }
}
