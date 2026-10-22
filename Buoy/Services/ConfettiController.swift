import AppKit
import QuartzCore

/// Easter egg: typing the word "confetti" in a note rains confetti over every
/// screen for a few seconds. Triggered from `BuoyTextView.insertText`.
///
/// One borderless window per screen, the way `FocusFogController` builds its
/// fog, except this one is transparent to the mouse and sits above everything,
/// panel and menu bar included. The windows are built per burst and torn down
/// once the last piece has landed, so nothing lingers between bursts.
///
/// Two party poppers fire up and inward from the bottom corners, then a short
/// fall drifts down from the top edge. Under Reduce Motion only a sparse,
/// slow fall plays.
final class ConfettiController {
    static let shared = ConfettiController()

    /// Above the panel, the fog (`FocusFogController.level`) and the menu bar.
    /// Click-through, so covering them costs nothing.
    private static let level = NSWindow.Level.screenSaver

    /// How long the windows stay up. The poppers' arc and the fall both land
    /// inside it; the last `fadeDuration` fades whatever is still in the air.
    private static let duration: TimeInterval = 4.2
    private static let reducedDuration: TimeInterval = 3
    private static let fadeDuration: TimeInterval = 0.6

    private var windows: [NSWindow] = []
    private var generation = 0

    private init() {}

    /// Ignored while a burst is already on screen, so typing the word twice in
    /// quick succession doesn't stack two sets of windows.
    func celebrate() {
        guard windows.isEmpty else { return }
        generation += 1
        let generation = generation
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let palette = Self.palette()

        windows = NSScreen.screens.map { screen in
            let window = ConfettiPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = Self.level
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let view = ConfettiView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.contentView = view
            window.orderFrontRegardless()
            view.start(palette: palette, reduced: reduced)
            return window
        }

        let total = reduced ? Self.reducedDuration : Self.duration
        DispatchQueue.main.asyncAfter(deadline: .now() + total - Self.fadeDuration) { [weak self] in
            guard let self, self.generation == generation else { return }
            let windows = self.windows
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                windows.forEach { $0.animator().alphaValue = 0 }
            } completionHandler: { [weak self] in
                guard let self, self.generation == generation else { return }
                self.windows.forEach { $0.orderOut(nil) }
                self.windows.removeAll()
            }
        }
    }

    /// The icon's yellow and its cyan float, the user's accent, then the
    /// party colours. White last, for sparkle against a dark desktop.
    private static func palette() -> [CGColor] {
        [
            NSColor(displayP3Red: 0.968, green: 0.903, blue: 0, alpha: 1),
            NSColor(displayP3Red: 0.18, green: 0.80, blue: 0.94, alpha: 1),
            BuoyTheme.current.accentNSColor,
            NSColor.systemOrange,
            NSColor.systemPink,
            NSColor.systemGreen,
            NSColor.white,
        ].map { $0.usingColorSpace(.displayP3)?.cgColor ?? $0.cgColor }
    }
}

// MARK: - Window

/// Never key or main, so the note keeps the keyboard while confetti falls.
private final class ConfettiPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - View

private final class ConfettiView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func start(palette: [CGColor], reduced: Bool) {
        guard let root = layer else { return }
        let size = bounds.size
        let scale = window?.backingScaleFactor ?? 2

        if reduced {
            root.addSublayer(fall(size: size, palette: palette, scale: scale, gentle: true, after: 0, for: 1.2))
            return
        }

        // Gravity and launch speed scale with the screen, so the arc peaks at
        // roughly the same share of its height on a laptop and on a 6K display.
        let gravity = max(size.height, 600) * 0.9
        let launch = (2 * gravity * size.height * 0.78).squareRoot()
        root.addSublayer(popper(at: CGPoint(x: 0, y: 0), aimedRight: true, launch: launch, gravity: gravity, palette: palette, scale: scale))
        root.addSublayer(popper(at: CGPoint(x: size.width, y: 0), aimedRight: false, launch: launch, gravity: gravity, palette: palette, scale: scale))
        root.addSublayer(fall(size: size, palette: palette, scale: scale, gentle: false, after: 0.35, for: 1.4))
    }

    /// A single short blast from a bottom corner, steeply up and inward.
    /// The layer's own coordinates are unflipped, so +y is up and angles run
    /// counter-clockwise from +x.
    private func popper(
        at point: CGPoint,
        aimedRight: Bool,
        launch: CGFloat,
        gravity: CGFloat,
        palette: [CGColor],
        scale: CGFloat
    ) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.renderMode = .unordered
        emitter.beginTime = CACurrentMediaTime()
        emitter.emitterCells = Self.cells(palette: palette, scale: scale) { cell in
            cell.birthRate = 900
            cell.lifetime = 4
            cell.velocity = launch
            cell.velocityRange = launch * 0.3
            cell.emissionLongitude = aimedRight ? .pi / 2 - 0.42 : .pi / 2 + 0.42
            cell.emissionRange = 0.32
            cell.yAcceleration = -gravity
            cell.spin = 3
            cell.spinRange = 10
        }
        stopEmitting(emitter, after: 0.22)
        return emitter
    }

    /// A curtain along the top edge, drifting down with a little sway.
    private func fall(
        size: CGSize,
        palette: [CGColor],
        scale: CGFloat,
        gentle: Bool,
        after delay: CFTimeInterval,
        for span: CFTimeInterval
    ) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: size.width / 2, y: size.height + 16)
        emitter.emitterSize = CGSize(width: size.width, height: 1)
        emitter.emitterShape = .line
        emitter.renderMode = .unordered
        emitter.beginTime = CACurrentMediaTime() + delay
        let speed: CGFloat = gentle ? 160 : 240
        emitter.emitterCells = Self.cells(palette: palette, scale: scale) { cell in
            cell.birthRate = Float(size.width / (gentle ? 40 : 8))
            cell.lifetime = gentle ? 3 : 4
            cell.velocity = speed
            cell.velocityRange = speed * 0.4
            cell.emissionLongitude = -.pi / 2
            cell.emissionRange = gentle ? 0.15 : 0.35
            cell.yAcceleration = gentle ? -40 : -110
            cell.spin = gentle ? 0.5 : 2
            cell.spinRange = gentle ? 1.5 : 6
        }
        stopEmitting(emitter, after: delay + span)
        return emitter
    }

    /// Particles already in the air keep flying; only new births stop.
    private func stopEmitting(_ emitter: CAEmitterLayer, after delay: CFTimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak emitter] in
            emitter?.birthRate = 0
        }
    }

    /// One ribbon and one dot cell per colour, sharing the burst's motion.
    /// Ribbons are three times as common as dots.
    private static func cells(
        palette: [CGColor],
        scale: CGFloat,
        configure: (CAEmitterCell) -> Void
    ) -> [CAEmitterCell] {
        let ribbon = image(size: CGSize(width: 4, height: 13), cornerRadius: 1, scale: scale)
        let dot = image(size: CGSize(width: 6, height: 6), cornerRadius: 3, scale: scale)
        let count = Float(palette.count)
        return palette.flatMap { color in
            [(ribbon, Float(0.75)), (dot, Float(0.25))].map { contents, share in
                let cell = CAEmitterCell()
                cell.contents = contents
                cell.contentsScale = scale
                cell.color = color
                cell.scale = 1
                cell.scaleRange = 0.3
                configure(cell)
                cell.birthRate *= share / count
                return cell
            }
        }
    }

    /// White so `CAEmitterCell.color` can tint it any colour.
    private static func image(size: CGSize, cornerRadius: CGFloat, scale: CGFloat) -> CGImage? {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let radius = cornerRadius * scale
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        return context.makeImage()
    }
}
