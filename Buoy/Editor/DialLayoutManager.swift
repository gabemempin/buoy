import AppKit

/// Dial Scrolling (Settings ▸ Appearance ▸ Text): lines near the top and
/// bottom of the editor tip away as if the note were printed on a wheel, the
/// way a watch's date or a picker drum curves out of view.
///
/// Drawing only. Each line fragment is drawn through its own transform, so
/// layout, hit testing, the caret and saved text never see the warp. That is
/// also why it stays subtle and confined to the edges: the further a line
/// is drawn from where it really is, the further a click lands from what the
/// user aimed at. The edge fade already softens the same band, so a click
/// there is rare.
///
/// The warp follows the edge fade's rule: an edge only curls when there is
/// text past it. A note scrolled to the top keeps its first line flat.
final class DialLayoutManager: NSLayoutManager {
    /// How far into the view the curve reaches from each edge, at most.
    static let maximumBand: CGFloat = 64
    /// The share of the visible height the band may take on a short panel.
    static let maximumBandFraction: CGFloat = 0.3
    /// The tilt of a line sitting right on the edge. A line's height is
    /// drawn at cos(angle), so 48° leaves it about two-thirds tall.
    static let edgeAngle: CGFloat = 48 * .pi / 180
    /// Perspective: the far side of the wheel is a little narrower.
    static let edgeWidthScale: CGFloat = 0.95

    /// The view to measure the visible band against. Set by `BuoyTextView`.
    weak var dialView: NSTextView?

    var isDialEnabled = false

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard isDialEnabled,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let view = dialView,
              let context = NSGraphicsContext.current?.cgContext
        else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        let visible = view.visibleRect
        let band = min(Self.maximumBand, visible.height * Self.maximumBandFraction)
        guard band > 1 else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        // How much text lies past each edge decides how strongly it curls,
        // ramping in over one band of scroll like the edge fade does.
        let textBottom = origin.y + (textContainers.first.map { usedRect(for: $0).maxY } ?? visible.maxY)
        let topStrength = Self.smoothstep((visible.minY - view.bounds.minY) / band)
        let bottomStrength = Self.smoothstep((textBottom - visible.maxY) / band)
        guard topStrength > 0 || bottomStrength > 0 else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        enumerateLineFragments(forGlyphRange: glyphsToShow) { _, usedRect, _, lineRange, _ in
            let range = NSIntersectionRange(lineRange, glyphsToShow)
            guard range.length > 0 else { return }
            let line = usedRect.offsetBy(dx: origin.x, dy: origin.y)

            // 0 outside the band, 1 on the edge. The view is flipped, so the
            // top edge is minY.
            let intoTop = (line.midY - visible.minY) / band
            let intoBottom = (visible.maxY - line.midY) / band
            let reach = max(
                topStrength * (1 - min(max(intoTop, 0), 1)),
                bottomStrength * (1 - min(max(intoBottom, 0), 1))
            )
            guard reach > 0.001 else {
                super.drawGlyphs(forGlyphRange: range, at: origin)
                return
            }

            // Eased so the curve starts gently at the band's inner edge
            // rather than kinking where flat text meets tilted text.
            let eased = reach * reach
            let heightScale = cos(Self.edgeAngle * eased)
            let widthScale = 1 - (1 - Self.edgeWidthScale) * eased
            // Lines tip about their own middle; the narrowing is about the
            // view's centre, which is where the wheel's axis would be.
            let pivot = CGPoint(x: visible.midX, y: line.midY)

            context.saveGState()
            context.translateBy(x: pivot.x, y: pivot.y)
            context.scaleBy(x: widthScale, y: heightScale)
            context.translateBy(x: -pivot.x, y: -pivot.y)
            super.drawGlyphs(forGlyphRange: range, at: origin)
            context.restoreGState()
        }
    }

    private static func smoothstep(_ value: CGFloat) -> CGFloat {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
