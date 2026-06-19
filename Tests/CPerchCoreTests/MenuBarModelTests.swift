import Testing
import Foundation
@testable import CPerchCore

// `menuBarModel` is a pure decision (v0.4 #10): aggregate + counts → abstract glyph
// and optional count. These feed it inputs directly (no Session plumbing) and pin
// each rule: the ≥2 threshold for the needs-you count, running carrying no count,
// and the all-done glyph gated on both "all concluded" and the preference.

@Suite("MenuBarModel — pure bar-dot decision")
struct MenuBarModelTests {

    @Test("no sessions → idle, no count")
    func empty() {
        let m = menuBarModel(aggregate: .idle, needsInputCount: 0,
                             allConcluded: false, allDoneGlyphEnabled: true)
        #expect(m == MenuBarModel(glyph: .idle, count: nil))
    }

    @Test("one needs-input → needsInput glyph, no count (below the ≥2 threshold)")
    func oneNeedsInput() {
        let m = menuBarModel(aggregate: .needsInput, needsInputCount: 1,
                             allConcluded: false, allDoneGlyphEnabled: true)
        #expect(m.glyph == .needsInput)
        #expect(m.count == nil)
    }

    @Test("three needs-input → needsInput glyph, count 3")
    func threeNeedsInput() {
        let m = menuBarModel(aggregate: .needsInput, needsInputCount: 3,
                             allConcluded: false, allDoneGlyphEnabled: true)
        #expect(m.glyph == .needsInput)
        #expect(m.count == 3)
    }

    @Test("running → running glyph, no count")
    func running() {
        let m = menuBarModel(aggregate: .running, needsInputCount: 0,
                             allConcluded: false, allDoneGlyphEnabled: true)
        #expect(m == MenuBarModel(glyph: .running, count: nil))
    }

    @Test("all concluded + glyph enabled → allDone glyph")
    func allDoneEnabled() {
        let m = menuBarModel(aggregate: .idle, needsInputCount: 0,
                             allConcluded: true, allDoneGlyphEnabled: true)
        #expect(m == MenuBarModel(glyph: .allDone, count: nil))
    }

    @Test("all concluded + glyph disabled → plain idle")
    func allDoneDisabled() {
        let m = menuBarModel(aggregate: .idle, needsInputCount: 0,
                             allConcluded: true, allDoneGlyphEnabled: false)
        #expect(m == MenuBarModel(glyph: .idle, count: nil))
    }

    @Test("needsInput aggregate with count 1 stays no-count")
    func needsInputCountOneNoCount() {
        let m = menuBarModel(aggregate: .needsInput, needsInputCount: 1,
                             allConcluded: false, allDoneGlyphEnabled: true)
        #expect(m.count == nil)
    }
}
