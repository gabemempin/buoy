import AppKit

final class TodoAttachment: NSTextAttachment {
    /// Keeps today's 19px circle at the default 13pt font.
    private static let sizeRatio: CGFloat = 19.0 / 13.0

    var isChecked: Bool {
        didSet { updateImage() }
    }
    var fontSize: CGFloat

    private(set) var displaySize: CGSize = CGSize(width: 19, height: 19)
    private(set) var yOffset: CGFloat = -3

    init(isChecked: Bool = false, fontSize: CGFloat = 13) {
        self.isChecked = isChecked
        self.fontSize = fontSize
        super.init(data: nil, ofType: nil)
        updateImage()
    }

    required init?(coder: NSCoder) {
        self.isChecked = false
        self.fontSize = 13
        super.init(coder: coder)
        updateImage()
    }

    /// Rescales the checkbox to match a new editor font size.
    func apply(fontSize: CGFloat) {
        guard fontSize != self.fontSize else { return }
        self.fontSize = fontSize
        updateImage()
    }

    private func updateImage() {
        let side = max(11, (fontSize * Self.sizeRatio).rounded())
        displaySize = CGSize(width: side, height: side)

        // Center the circle on the trailing text's cap height (matches the visual
        // center of capitalized text better than x-height).
        let f = NSFont.systemFont(ofSize: fontSize)
        yOffset = ((f.capHeight - side) / 2).rounded()

        let lineWidth = max(1, side * 0.085)
        let image = NSImage(size: displaySize, flipped: false) { rect in
            let c = rect.insetBy(dx: side * 0.06, dy: side * 0.06)
            if self.isChecked {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn: c).fill()

                NSColor.white.setStroke()
                let check = NSBezierPath()
                check.lineWidth = lineWidth
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                // Centered checkmark (non-flipped coords: y up). Nudged up-and-right so the
                // glyph reads as optically centered within the circle.
                check.move(to: CGPoint(x: c.minX + c.width * 0.26, y: c.midY + c.height * 0.04))
                check.line(to: CGPoint(x: c.minX + c.width * 0.41, y: c.minY + c.height * 0.33))
                check.line(to: CGPoint(x: c.maxX - c.width * 0.25, y: c.maxY - c.height * 0.30))
                check.stroke()
            } else {
                let path = NSBezierPath(ovalIn: c)
                NSColor.secondaryLabelColor.setStroke()
                path.lineWidth = lineWidth
                path.stroke()
            }
            return true
        }
        self.image = image
        self.bounds = CGRect(origin: CGPoint(x: 0, y: yOffset), size: displaySize)
    }
}
