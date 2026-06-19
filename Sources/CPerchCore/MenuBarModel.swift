import Foundation

// cPerch — the menu-bar dot's display model (v0.4 #10). A pure, Foundation-only
// decision: given the already-computed aggregate state and a couple of counts, it
// says which abstract glyph the bar should show and whether to append a count.
//
// Kept in CPerchCore so it's unit-tested without AppKit. The `Glyph` is ABSTRACT —
// it carries no color. The App layer (MenuBarController) maps each case to a design
// token color and renders the dot + optional count. No AppKit/SwiftUI here.

/// What the menu bar shows: an abstract glyph plus an optional count.
public struct MenuBarModel: Equatable, Sendable {
    /// Abstract bar glyph. Colors live in the App layer (mapped from these cases).
    public enum Glyph: Sendable, Equatable { case idle, running, needsInput, allDone }
    public let glyph: Glyph
    public let count: Int?          // shown only when ≥2 need input; else nil
    public init(glyph: Glyph, count: Int?) { self.glyph = glyph; self.count = count }
}

/// Pure decision for the menu-bar dot. Inputs are pre-computed by the caller.
///
/// Pure and Foundation-only — no AppKit/SwiftUI. The returned `Glyph` is abstract;
/// the App layer maps it to a color (needsInput→orange, running→blue, idle→gray,
/// allDone→green) and draws the dot.
///
/// Rules:
/// - `.needsInput` aggregate → `.needsInput`, count shown only when `needsInputCount >= 2`.
/// - `.running` aggregate → `.running`, no count.
/// - `.idle` aggregate → `.allDone` when everything concluded *and* the glyph is enabled,
///   otherwise `.idle`; never a count.
public func menuBarModel(aggregate: AggregateState, needsInputCount: Int,
                         allConcluded: Bool, allDoneGlyphEnabled: Bool) -> MenuBarModel {
    switch aggregate {
    case .needsInput:
        return MenuBarModel(glyph: .needsInput, count: needsInputCount >= 2 ? needsInputCount : nil)
    case .running:
        return MenuBarModel(glyph: .running, count: nil)
    case .idle:
        let glyph: MenuBarModel.Glyph = (allConcluded && allDoneGlyphEnabled) ? .allDone : .idle
        return MenuBarModel(glyph: glyph, count: nil)
    }
}
