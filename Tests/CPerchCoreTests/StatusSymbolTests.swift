import Testing
@testable import CPerchCore

// `statusSymbol(for:)` is the pure, color-free decision of WHICH abstract symbol a status
// shows (v0.5 A1) — the App layer maps the result to an SF Symbol name + color. These pin the
// two overloads: the roster's `DerivedStatus` and the menu bar's `MenuBarModel.Glyph`
// (where allDone reuses the concluded check, and idle is the resting dot).

@Suite("StatusSymbol — status / glyph → abstract symbol")
struct StatusSymbolTests {

    @Test("DerivedStatus maps to its symbol")
    func fromStatus() {
        #expect(statusSymbol(for: DerivedStatus.needsInput) == .needsInput)
        #expect(statusSymbol(for: DerivedStatus.running) == .running)
        #expect(statusSymbol(for: DerivedStatus.concluded) == .concluded)
    }

    @Test("MenuBarModel.Glyph maps — allDone → concluded, idle → idle")
    func fromGlyph() {
        #expect(statusSymbol(for: MenuBarModel.Glyph.needsInput) == .needsInput)
        #expect(statusSymbol(for: MenuBarModel.Glyph.running) == .running)
        #expect(statusSymbol(for: MenuBarModel.Glyph.allDone) == .concluded)
        #expect(statusSymbol(for: MenuBarModel.Glyph.idle) == .idle)
    }
}
