import AppKit

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
        let size = CGSize(width: 19, height: 19)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = rect.insetBy(dx: 1, dy: 1)
            if self.isChecked {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn: circle).fill()
                NSColor.white.setStroke()
                let check = NSBezierPath()
                check.lineWidth = 1.5
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.move(to: CGPoint(x: circle.minX + 3.5, y: circle.midY))
                check.line(to: CGPoint(x: circle.minX + 6, y: circle.minY + 4))
                check.line(to: CGPoint(x: circle.maxX - 3, y: circle.maxY - 3))
                check.stroke()
            } else {
                let path = NSBezierPath(ovalIn: circle)
                NSColor.tertiaryLabelColor.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
            return true
        }
        self.image = image
        self.bounds = CGRect(origin: CGPoint(x: 0, y: -3), size: size)
    }

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
