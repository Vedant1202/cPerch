import AppKit

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
enum Tokens {
    static let needsInput = NSColor(hex: 0xD97757)  // orange — primary accent
    static let running    = NSColor(hex: 0x6A9BCC)  // blue — secondary accent
    static let idleDim     = NSColor(hex: 0xB0AEA5)  // mid gray — dim/idle
}
