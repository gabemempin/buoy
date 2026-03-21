import AppKit

/// NSTextAttachment subclass that renders as a checkbox.
/// Used inline in NSTextView to represent to-do items.
final class TodoAttachment: NSTextAttachment {
    var isChecked: Bool {
        didSet { updateImage() }
    }

    init(isChecked: Bool = false) {
        self.isChecked = isChecked
        super.init(data: nil, ofType: nil)
        updateImage()
    }

    required init?(coder: NSCoder) {
        self.isChecked = false
        super.init(coder: coder)
        updateImage()
    }

    private func updateImage() {
        let size = CGSize(width: 17, height: 17)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = rect.insetBy(dx: 1, dy: 1)
            if self.isChecked {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn: circle).fill()
                // Checkmark
                NSColor.white.setStroke()
                let check = NSBezierPath()
                check.lineWidth = 1.5
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                let inset: CGFloat = 3.5
                let checkRect = circle.insetBy(dx: inset, dy: inset)
                check.move(to: CGPoint(x: checkRect.minX, y: checkRect.midY))
                check.line(to: CGPoint(x: checkRect.minX + checkRect.width * 0.35, y: checkRect.minY))
                check.line(to: CGPoint(x: checkRect.maxX, y: checkRect.maxY))
                check.stroke()
            } else {
                let path = NSBezierPath(ovalIn: circle)
                NSColor.tertiaryLabelColor.setStroke()
                path.lineWidth = 1.0
                path.stroke()
            }
            return true
        }
        self.image = image
        self.bounds = CGRect(origin: CGPoint(x: 0, y: -2), size: size)
    }

    // MARK: - Archiving support

    func encode() -> Data? {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(isChecked, forKey: "isChecked")
        archiver.finishEncoding()
        return archiver.encodedData
    }

    static func decode(from data: Data) -> TodoAttachment? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        let checked = unarchiver.decodeBool(forKey: "isChecked")
        return TodoAttachment(isChecked: checked)
    }
}
