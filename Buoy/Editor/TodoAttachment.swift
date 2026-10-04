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

    private static let toggleDuration: TimeInterval = 0.32
    /// 0 when a toggle starts, 1 at rest.
    private var toggleProgress: CGFloat = 1
    private var toggleTimer: Timer?

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

    /// Redraws the checkbox after the accent colour changes.
    ///
    /// The colours are baked into an `NSImage` at construction, so an
    /// attachment already sitting in the text storage keeps the old accent
    /// until something asks it to redraw. `BuoyTextView` walks its storage on
    /// `.buoyThemeDidChange` and calls this on every one.
    func refreshForThemeChange() {
        updateImage()
    }

    /// Toggles the box, animating the change unless Reduce Motion is on.
    ///
    /// The glyph is a baked image, so each frame rebuilds it and `redraw`
    /// asks the text view to repaint the attachment's character.
    func setChecked(_ checked: Bool, animated: Bool, redraw: @escaping () -> Void) {
        toggleTimer?.invalidate()
        toggleTimer = nil
        let duration = animated ? BuoyMotion.duration(Self.toggleDuration) : 0
        guard duration > 0 else {
            toggleProgress = 1
            isChecked = checked
            redraw()
            return
        }

        toggleProgress = 0
        isChecked = checked
        redraw()
        let start = ProcessInfo.processInfo.systemUptime
        // `.common` so frames keep coming while the mouse-tracking loop that
        // delivered the click is still spinning in `.eventTracking`.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.toggleProgress = Self.clamp(CGFloat((ProcessInfo.processInfo.systemUptime - start) / duration))
            self.updateImage()
            redraw()
            if self.toggleProgress >= 1 {
                timer.invalidate()
                self.toggleTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        toggleTimer = timer
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
        // Captured now: the handler can run later, mid-animation or after it.
        let checked = isChecked
        let progress = toggleProgress
        let image = NSImage(size: displaySize, flipped: false) { rect in
            let c = rect.insetBy(dx: side * 0.06, dy: side * 0.06)
            let isDark = NSAppearance.currentDrawing()
                .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

            // Checking: the fill pops in with a slight overshoot while the
            // ring fades, then the check draws itself in. Unchecking: the fill
            // shrinks away and the ring returns. At progress 1 both reduce to
            // the static glyph.
            let ringAlpha: CGFloat
            let fillScale: CGFloat
            let fillAlpha: CGFloat
            let checkDrawn: CGFloat
            if checked {
                ringAlpha = 1 - Self.clamp(progress / 0.3)
                fillScale = 0.55 + 0.45 * Self.easeOutBack(Self.clamp(progress / 0.6))
                fillAlpha = Self.clamp(progress / 0.2)
                checkDrawn = Self.easeOut(Self.clamp((progress - 0.3) / 0.7))
            } else {
                let t = Self.easeOut(progress)
                ringAlpha = t
                fillScale = 1 - 0.3 * t
                fillAlpha = 1 - t
                checkDrawn = 0
            }

            if ringAlpha > 0 {
                // A stroke straddles its path, so inset by half the line width
                // or the ring's outer edge lands outside the checked fill.
                let ring = NSBezierPath(ovalIn: c.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
                BuoyTheme.current.accentText(isDark: isDark)
                    .withAlphaComponent(ringAlpha).setStroke()
                ring.lineWidth = lineWidth
                ring.stroke()
            }

            if fillAlpha > 0 {
                let inset = c.width * (1 - fillScale) / 2
                BuoyTheme.current.accentNSColor.withAlphaComponent(fillAlpha).setFill()
                NSBezierPath(ovalIn: c.insetBy(dx: inset, dy: inset)).fill()
            }

            if checkDrawn > 0 {
                // Non-flipped coords: y up. Traced from SF Symbols'
                // `checkmark.circle.fill`: a short arm and a steep long arm.
                // A wide 45° check with a thicker stroke was centred to the
                // pixel and still read as sunk low-left in the circle.
                let a = CGPoint(x: c.minX + c.width * 0.30, y: c.minY + c.height * 0.47)
                let b = CGPoint(x: c.minX + c.width * 0.445, y: c.minY + c.height * 0.30)
                let e = CGPoint(x: c.minX + c.width * 0.69, y: c.minY + c.height * 0.675)
                let short = hypot(b.x - a.x, b.y - a.y)
                let long = hypot(e.x - b.x, e.y - b.y)
                let drawn = checkDrawn * (short + long)

                let check = NSBezierPath()
                check.lineWidth = max(1, c.width * 0.076)
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.move(to: a)
                if drawn <= short {
                    check.line(to: Self.lerp(a, b, drawn / short))
                } else {
                    check.line(to: b)
                    check.line(to: Self.lerp(b, e, (drawn - short) / long))
                }
                BuoyTheme.current.onAccentNSColor.setStroke()
                check.stroke()
            }
            return true
        }
        // An image attachment otherwise reaches VoiceOver as an anonymous
        // "attachment", so a to-do list is unusable — the checked state is the
        // whole point of the glyph. AppKit reads this off the attachment's image.
        image.accessibilityDescription = isChecked ? "Checked to-do" : "Unchecked to-do"
        self.image = image
        self.bounds = CGRect(origin: CGPoint(x: 0, y: yOffset), size: displaySize)
    }

    private static func clamp(_ t: CGFloat) -> CGFloat { min(1, max(0, t)) }

    private static func easeOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - t, 3) }

    /// Overshoots by about 10% before settling, so the fill reads as a pop.
    private static func easeOutBack(_ t: CGFloat) -> CGFloat {
        let s: CGFloat = 1.70158
        let u = t - 1
        return 1 + (s + 1) * u * u * u + s * u * u
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
