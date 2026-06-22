import SwiftUI

// The cPerch bird mark as a resolution-independent SwiftUI shape, traced from
// assets/brand/cperch-mark.svg (the brand silhouette, without the terminal prompt — that
// reads only at large sizes). Used in the popover, Settings, and Help headers. The live
// menu-bar glyph is drawn separately in MenuBarController; this is the in-app chrome mark.

/// The bird silhouette. Filled even-odd so the small eye reads as a cut-out at larger sizes.
struct CPerchBird: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 112, sy = rect.height / 64   // design-space box: x 6…118, y 16…80
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (x - 6) * sx, y: rect.minY + (y - 16) * sy)
        }
        var path = Path()
        path.move(to: p(118, 34))
        path.addCurve(to: p(98, 18),  control1: p(112, 26), control2: p(106, 20))
        path.addCurve(to: p(76, 24),  control1: p(90, 16),  control2: p(82, 18))
        path.addCurve(to: p(48, 40),  control1: p(66, 32),  control2: p(56, 36))
        path.addCurve(to: p(36, 47),  control1: p(44, 42),  control2: p(40, 44))
        path.addCurve(to: p(6, 80),   control1: p(28, 55),  control2: p(16, 66))
        path.addCurve(to: p(40, 62),  control1: p(16, 72),  control2: p(28, 66))
        path.addCurve(to: p(70, 69),  control1: p(52, 66),  control2: p(60, 70))
        path.addCurve(to: p(100, 50), control1: p(84, 68),  control2: p(94, 60))
        path.addCurve(to: p(118, 34), control1: p(104, 44), control2: p(108, 40))
        path.closeSubpath()
        // Eye — an even-odd hole, visible only at larger sizes.
        let eye = p(99, 29), r = 2.7 * sx
        path.addEllipse(in: CGRect(x: eye.x - r, y: eye.y - r, width: r * 2, height: r * 2))
        return path
    }
}

/// The cPerch bird as a sized, colored view that keeps the mark's aspect. Defaults to the
/// primary label color so it reads as chrome, not a status accent.
struct CPerchMark: View {
    var color: Color = .primary
    var height: CGFloat = 16
    var body: some View {
        CPerchBird()
            .fill(color, style: FillStyle(eoFill: true))
            .frame(width: height * 112 / 64, height: height)
            .accessibilityHidden(true)
    }
}
