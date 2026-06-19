import Foundation

// cPerch — the abstract status symbol (v0.5 A1, shape-coded status). A pure, color-free
// decision of WHICH symbol a status shows, so the roster and the menu bar agree and the
// rule is unit-tested. The App layer maps each case to a concrete SF Symbol *name* and a
// design-token color (SF Symbols isn't Foundation, so the name lives in CPerchApp/DesignTokens).
//
// Mirrors the existing `MenuBarModel.Glyph` precedent: an abstract case here, the concrete
// rendering in CPerchApp.

/// Abstract status symbol. Maps 1:1 to an SF Symbol in the App layer
/// (needsInput → exclamationmark.triangle.fill, running → circle.lefthalf.filled,
/// concluded → checkmark.circle.fill, idle → circle.fill). Carries no color.
public enum StatusSymbol: Sendable, Equatable {
    case needsInput, running, concluded, idle
}

/// The symbol for a roster row's status.
public func statusSymbol(for status: DerivedStatus) -> StatusSymbol {
    switch status {
    case .needsInput: return .needsInput
    case .running:    return .running
    case .concluded:  return .concluded
    }
}

/// The symbol for the menu-bar aggregate glyph. `allDone` reuses the concluded check (everything
/// finished); `idle` is the resting dot.
public func statusSymbol(for glyph: MenuBarModel.Glyph) -> StatusSymbol {
    switch glyph {
    case .needsInput: return .needsInput
    case .running:    return .running
    case .allDone:    return .concluded
    case .idle:       return .idle
    }
}
