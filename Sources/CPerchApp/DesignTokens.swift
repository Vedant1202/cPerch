import AppKit
import SwiftUI
import CPerchCore

extension NSColor {
    /// 0xRRGGBB → sRGB color.
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

/// Claude brand tokens — see docs/design/design-tokens.md.
/// The accent dots stay the same in light/dark; surfaces/text follow the system.
enum Tokens {
    static let needsInput = NSColor(hex: 0xD97757)  // orange — primary accent
    static let running    = NSColor(hex: 0x6A9BCC)  // blue — secondary accent
    static let concluded  = NSColor(hex: 0x788C5D)  // green — tertiary accent
    static let idleDim    = NSColor(hex: 0xB0AEA5)  // mid gray — dim/idle
    static let midGray    = NSColor(hex: 0xB0AEA5)  // secondary text / icons
    static let divider    = NSColor(hex: 0xE8E6DC)  // subtle fills / dividers
}

// SwiftUI bridges — the roster (RosterView) is SwiftUI, the bar dot is AppKit.
extension Color {
    init(_ nsColor: NSColor) { self = Color(nsColor: nsColor) }
}

enum TokenColors {
    static let needsInput = Color(Tokens.needsInput)
    static let running    = Color(Tokens.running)
    static let concluded  = Color(Tokens.concluded)
    static let midGray    = Color(Tokens.midGray)
    static let divider    = Color(Tokens.divider)
}

/// Brand fonts: Inter-ish UI body + JetBrains-Mono-ish for code/preview, with
/// graceful native fallback (SF Pro / system monospace) when not installed.
enum TokenFonts {
    /// UI / body — Inter ≈ Styrene B, falls back to the system font.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "Inter", size: size) != nil {
            return .custom("Inter", size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }

    /// Code / message preview — JetBrains Mono, falls back to system monospace.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "JetBrains Mono", size: size) != nil {
            return .custom("JetBrains Mono", size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Accessibility vocabulary (v0.5) — consumed by RosterView (Track R) + MenuBarController (Track M)

extension Tokens {
    /// High-contrast status fills (A3). Verified ≥4.5:1 on light (`#FAF9F5`/white), ≥7:1 on dark
    /// (`#141413`). The *standard* palette keeps the brand accents (dark already passes; light leans
    /// on the always-on shape + a hairline ring), so only high contrast swaps the fill.
    enum HC {
        static let needsInputLight = NSColor(hex: 0xAB5E45)
        static let runningLight    = NSColor(hex: 0x51769B)
        static let concludedLight  = NSColor(hex: 0x677850)
        static let needsInputDark  = NSColor(hex: 0xDF8B70)
        static let runningDark     = NSColor(hex: 0x77A4D1)
        static let concludedDark   = NSColor(hex: 0x96A581)
    }

    /// The fill color for a status, honoring high contrast + the active appearance (A2/A3).
    static func statusColor(_ status: DerivedStatus, highContrast: Bool, dark: Bool) -> NSColor {
        switch status {
        case .needsInput: return highContrast ? (dark ? HC.needsInputDark : HC.needsInputLight) : needsInput
        case .running:    return highContrast ? (dark ? HC.runningDark    : HC.runningLight)    : running
        case .concluded:  return highContrast ? (dark ? HC.concludedDark  : HC.concludedLight)  : concluded
        }
    }

    /// On-device fallback flip (A1): if the triangle / half-disc read too busy at 9 pt, set `true`
    /// for the cohesive all-circle family. The locked default keeps the distinct-silhouette set.
    static let useCircleFallback = false

    /// The concrete SF Symbol name for an abstract `StatusSymbol` (A1).
    static func symbolName(for symbol: StatusSymbol) -> String {
        switch symbol {
        case .needsInput: return useCircleFallback ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill"
        case .running:    return useCircleFallback ? "ellipsis.circle.fill"        : "circle.lefthalf.filled"
        case .concluded:  return "checkmark.circle.fill"
        case .idle:       return "circle.fill"
        }
    }
}

extension TokenColors {
    /// Semantic text / line colors (A2) — adapt to light/dark AND auto-boost under macOS Increase
    /// Contrast, fixing the measured light-mode failures (e.g. preview text at 2.11:1) for everyone.
    /// These replace hardcoded `midGray` / `divider` at the roster's secondary sites.
    static let secondaryText = Color(NSColor.secondaryLabelColor)
    static let tertiaryText  = Color(NSColor.tertiaryLabelColor)
    static let separator     = Color(NSColor.separatorColor)
}
