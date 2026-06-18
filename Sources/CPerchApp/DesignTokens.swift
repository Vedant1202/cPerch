import AppKit
import SwiftUI

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
