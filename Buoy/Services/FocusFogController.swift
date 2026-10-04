import AppKit
import AVFoundation
import SwiftUI
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Focus fog: covers the rest of the desktop with a heavily blurred copy of
/// the user's own wallpaper, or a moving mesh gradient in its colours
/// (`FocusFogStyle`), so the note is the only sharp thing on screen.
/// Toggled by shaking the header (see `DragEnablingNSView`), owned by
/// `AppDelegate`.
///
/// One borderless window per screen that swallows every click, sitting just *below* the
/// panel. It never becomes key, so typing keeps going to the note.
///
/// The blurred wallpaper is rendered ahead of time (`prepare()`, at launch and
/// after every hide) and the windows are kept built, so a shake only has to
/// order a window in and start the fade. Rendering on demand decoded a 6K HEIC
/// first, which showed up as a beat of nothing before the fog moved.
final class FocusFogController {
    /// Under `.floating` so the panel can sit on top of it without being
    /// pushed to `.statusBar`. `AppDelegate.panelWindowLevel` lifts the panel
    /// to at least `.floating` while the fog is up; a panel left at `.normal`
    /// would end up *behind* the fog.
    static let level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)

    private(set) var isActive = false
    private var windows: [NSWindow] = []
    private var fogAssets: [WallpaperKey: FogAssets] = [:]
    private(set) var style: FocusFogStyle = .wallpaperBlur
    private var rendering: Set<WallpaperKey> = []
    private var renderCallbacks: [() -> Void] = []
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var generation = 0

    /// Ease-out so the fog is visibly moving from the first frame; an
    /// ease-in-out start reads as a delay.
    private let fadeInDuration: TimeInterval = 0.55
    private let fadeOutDuration: TimeInterval = 0.4

    /// Never fully opaque. An opaque full-screen window counts as covering
    /// everything under it, so macOS lets the desktop drop its wallpaper
    /// while the fog is up; the first fade out then revealed black until the
    /// wallpaper redrew. At 0.99 nothing underneath is ever occluded, and the
    /// 1% that shows through is lost in the blur.
    private let shownAlpha: CGFloat = 0.99

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.tearDownWindows()
            if self.isActive {
                self.buildWindows()
                self.present(animated: false)
            }
            self.prepare()
        }
        // Each Space can have its own wallpaper.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.prepare() }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }

    /// Renders each screen's fog in the background so the next `show()` is
    /// instant. Cheap to call when nothing changed: it only reads metadata.
    func prepare(completion: (() -> Void)? = nil) {
        let missing = Set(NSScreen.screens.map(WallpaperKey.init(screen:)))
            .filter { fogAssets[$0] == nil && !rendering.contains($0) }
        if let completion {
            if missing.isEmpty && rendering.isEmpty {
                completion()
                return
            }
            renderCallbacks.append(completion)
        }
        guard !missing.isEmpty else { return }
        rendering.formUnion(missing)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let rendered = missing.map { ($0, WallpaperFog.render($0)) }
            DispatchQueue.main.async {
                guard let self else { return }
                for (key, assets) in rendered {
                    self.rendering.remove(key)
                    if let assets { self.fogAssets[key] = assets }
                }
                guard self.rendering.isEmpty else { return }
                let callbacks = self.renderCallbacks
                self.renderCallbacks.removeAll()
                callbacks.forEach { $0() }
            }
        }
    }

    func show(style: FocusFogStyle) {
        guard !isActive else { return }
        self.style = style
        isActive = true
        generation += 1
        let expected = generation
        // Normally already rendered by `prepare()`; only a wallpaper change
        // since the last hide (or a dynamic wallpaper ticking over to its next
        // frame) waits here.
        prepare { [weak self] in
            guard let self, self.isActive, self.generation == expected else { return }
            if self.windows.count != NSScreen.screens.count { self.buildWindows() }
            self.present(animated: true)
        }
    }

    /// Restyles the fog in place if it is up; otherwise just remembered.
    func setStyle(_ style: FocusFogStyle) {
        guard style != self.style else { return }
        self.style = style
        guard isActive else { return }
        for (window, screen) in zip(windows, NSScreen.screens) {
            applyContent(to: window, screen: screen)
        }
    }

    func hide(animated: Bool = true) {
        guard isActive else { return }
        isActive = false
        generation += 1
        guard animated else {
            windows.forEach(retire)
            prepare()
            return
        }
        let expected = generation
        fade(to: 0, duration: fadeOutDuration, timing: .easeIn) { [weak self] in
            // A show that landed mid-fade owns the windows now.
            guard let self, self.generation == expected else { return }
            self.windows.forEach(self.retire)
            self.prepare()
        }
    }

    // MARK: - Windows

    /// Ordered out, with the gradient's timeline unmounted so nothing keeps
    /// ticking while the fog is down.
    private func retire(_ window: NSWindow) {
        window.orderOut(nil)
        (window.contentView as? FogView)?.stopAnimating()
    }

    private func applyContent(to window: NSWindow, screen: NSScreen) {
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let assets = fogAssets[WallpaperKey(screen: screen)]
        // An unreadable wallpaper still gets a gradient, from its fill colour.
        let palette = assets?.palette
            ?? FogPalette.make(from: (options[.fillColor] as? NSColor)?.usingColorSpace(.sRGB))
        (window.contentView as? FogView)?.apply(
            image: assets?.blur,
            palette: palette,
            style: style,
            options: options
        )
    }

    private func present(animated: Bool) {
        for (window, screen) in zip(windows, NSScreen.screens) {
            window.setFrame(screen.frame, display: false)
            applyContent(to: window, screen: screen)
            window.alphaValue = animated ? 0 : shownAlpha
            window.orderFront(nil)
        }
        guard animated else { return }
        // Let the order-in reach the window server before the fade starts, so
        // its first frames aren't spent on that commit.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive else { return }
            self.fade(to: self.shownAlpha, duration: self.fadeInDuration, timing: .easeOut)
        }
    }

    private func buildWindows() {
        tearDownWindows()
        windows = NSScreen.screens.map { screen in
            // A non-activating panel, so the clicks it swallows don't
            // activate Buoy or pull focus away from the note.
            let window = FogPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            // Opaque to the mouse: the fog is a wall, not a tint, so nothing
            // behind it can be clicked, scrolled or hovered while it's up.
            window.ignoresMouseEvents = false
            window.level = Self.level
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.alphaValue = 0
            window.contentView = FogView(frame: NSRect(origin: .zero, size: screen.frame.size))
            return window
        }
    }

    private func tearDownWindows() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }

    private func fade(
        to alpha: CGFloat,
        duration: TimeInterval,
        timing: CAMediaTimingFunctionName,
        completion: (() -> Void)? = nil
    ) {
        let windows = windows
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: timing)
            windows.forEach { $0.animator().alphaValue = alpha }
        } completionHandler: {
            completion?()
        }
    }
}

// MARK: - Wallpaper

/// Which wallpaper image (and which frame of a dynamic one) a screen shows.
private struct WallpaperKey: Hashable {
    let url: URL?
    let frameIndex: Int

    init(screen: NSScreen) {
        url = NSWorkspace.shared.desktopImageURL(for: screen)
        frameIndex = url.map(WallpaperFog.currentFrameIndex(of:)) ?? 0
    }
}

private enum WallpaperFog {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    /// The result is blurred to mush anyway, so a small decode is enough and
    /// keeps a 6K HEIC to a few milliseconds.
    private static let maxPixelSize = 960
    private static let blurSigma: Double = 16

    /// Covers still images (JPEG, PNG, HEIC, Apple's solid colours, which
    /// are PNGs), dynamic HEICs, and video wallpapers. Returns `nil` for
    /// anything unreadable (a folder, a missing file), and the view falls
    /// back to a live blur.
    static func render(_ key: WallpaperKey) -> FogAssets? {
        guard let url = key.url,
              let thumbnail = stillFrame(of: url, index: key.frameIndex) ?? videoFrame(of: url)
        else { return nil }

        let input = CIImage(cgImage: thumbnail)
        let fog = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: blurSigma)
            .cropped(to: input.extent)
        guard let blur = context.createCGImage(fog, from: input.extent) else { return nil }
        return FogAssets(blur: blur, palette: FogPalette.make(from: thumbnail))
    }

    private static func stillFrame(of url: URL, index: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        let index = min(index, CGImageSourceGetCount(source) - 1)
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    /// Aerial-style wallpapers are movies. The first frame is close enough
    /// once it's blurred. Called off the main thread, so blocking is fine.
    private static func videoFrame(of url: URL) -> CGImage? {
        guard let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .movie)
        else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)

        var frame: CGImage?
        let done = DispatchSemaphore(value: 0)
        generator.generateCGImageAsynchronously(for: .zero) { image, _, _ in
            frame = image
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
        return frame
    }

    /// The frame the desktop is showing right now. Dynamic wallpapers carry a
    /// base64 plist in their XMP: `h24` maps time of day to frames, `solar`
    /// and `apr` carry a light/dark pair (`ap`, or `l`/`d` at the top level).
    static func currentFrameIndex(of url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 1,
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        else { return 0 }

        func plist(_ path: String) -> [String: Any]? {
            guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
                  let value = CGImageMetadataTagCopyValue(tag) as? String,
                  let data = Data(base64Encoded: value)
            else { return nil }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        }

        if let h24 = plist("apple_desktop:h24"),
           let entries = h24["ti"] as? [[String: Any]] {
            let now = Date()
            let midnight = Calendar.current.startOfDay(for: now)
            let fraction = now.timeIntervalSince(midnight) / 86_400
            let frames = entries.compactMap { entry -> (t: Double, i: Int)? in
                guard let t = (entry["t"] as? NSNumber)?.doubleValue,
                      let i = (entry["i"] as? NSNumber)?.intValue
                else { return nil }
                return (t, i)
            }.sorted { $0.t < $1.t }
            // The last frame that has started today, wrapping to last night's.
            if let current = frames.last(where: { $0.t <= fraction }) ?? frames.last {
                return current.i
            }
        }

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        for path in ["apple_desktop:solar", "apple_desktop:apr"] {
            guard let dict = plist(path) else { continue }
            let pair = (dict["ap"] as? [String: Any]) ?? dict
            if let index = (pair[isDark ? "d" : "l"] as? NSNumber)?.intValue {
                return index
            }
        }
        return 0
    }
}

// MARK: - Window

/// Never key or main, so a click on the fog leaves the note focused.
private final class FogPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - View

/// Just the blurred wallpaper. No tint or mist on top: anything layered over
/// it read as a white wash rather than the user's own desktop. Without a
/// readable wallpaper it falls back to a live backdrop blur.
private final class FogView: NSView {
    private let fallbackBlur = NSVisualEffectView()
    /// Its own subview, so AppKit can't slide the layer under the blur.
    private let overlay = NSView()
    private let wallpaper = CALayer()
    /// The gradient: two pre-rendered mesh images turning in opposite
    /// directions, the top one breathing in and out. All Core Animation, so
    /// the motion runs in the window server and never depends on the app
    /// redrawing. (A SwiftUI `TimelineView` here rendered one frame and then
    /// sat still.)
    private let gradientView = NSView()
    private let meshLayers = [CALayer(), CALayer()]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        fallbackBlur.material = .hudWindow
        fallbackBlur.blendingMode = .behindWindow
        fallbackBlur.state = .active
        fallbackBlur.frame = bounds
        fallbackBlur.autoresizingMask = [.width, .height]
        fallbackBlur.isHidden = true
        addSubview(fallbackBlur)

        overlay.wantsLayer = true
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)
        wallpaper.contentsGravity = .resizeAspectFill
        overlay.layer?.addSublayer(wallpaper)

        gradientView.wantsLayer = true
        gradientView.frame = bounds
        gradientView.autoresizingMask = [.width, .height]
        gradientView.isHidden = true
        addSubview(gradientView)
        for mesh in meshLayers {
            mesh.contentsGravity = .resize
            gradientView.layer?.addSublayer(mesh)
        }
        meshLayers[1].opacity = 0.55
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(
        image: CGImage?,
        palette: [CGColor],
        style: FocusFogStyle,
        options: [NSWorkspace.DesktopImageOptionKey: Any]
    ) {
        switch style {
        case .wallpaperBlur:
            stopAnimating()
            overlay.isHidden = false
            applyWallpaper(image, options: options)
        case .gradient:
            overlay.isHidden = true
            fallbackBlur.isHidden = true
            gradientView.isHidden = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            meshLayers[0].contents = FogMeshImage.render(palette)
            // Same colours in reverse, so the overlap keeps shifting hue.
            meshLayers[1].contents = FogMeshImage.render(Array(palette.reversed()))
            CATransaction.commit()
            startAnimating()
        }
    }

    private func startAnimating() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            meshLayers.forEach { $0.removeAllAnimations() }
            return
        }
        for (mesh, (period, direction)) in zip(meshLayers, [(90.0, 1.0), (130.0, -1.0)])
        where mesh.animation(forKey: "spin") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = direction * 2 * Double.pi
            spin.duration = period
            spin.repeatCount = .infinity
            mesh.add(spin, forKey: "spin")
        }
        if meshLayers[1].animation(forKey: "breathe") == nil {
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 0.2
            breathe.toValue = 0.85
            breathe.duration = 9
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            meshLayers[1].add(breathe, forKey: "breathe")
        }
    }

    /// Stops the gradient's motion while the fog is down; it restarts on the
    /// next `apply`.
    func stopAnimating() {
        meshLayers.forEach { $0.removeAllAnimations() }
        gradientView.isHidden = true
    }

    /// Lays the fog out the way the desktop lays out the wallpaper.
    private func applyWallpaper(_ image: CGImage?, options: [NSWorkspace.DesktopImageOptionKey: Any]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wallpaper.contents = image
        fallbackBlur.isHidden = image != nil

        let clips = (options[.allowClipping] as? NSNumber)?.boolValue ?? true
        let scaling = (options[.imageScaling] as? NSNumber)
            .flatMap { NSImageScaling(rawValue: $0.uintValue) } ?? .scaleProportionallyUpOrDown
        switch scaling {
        case .scaleAxesIndependently: wallpaper.contentsGravity = .resize
        case .scaleNone: wallpaper.contentsGravity = .center
        default: wallpaper.contentsGravity = clips ? .resizeAspectFill : .resizeAspect
        }
        let fill = (options[.fillColor] as? NSColor) ?? .black
        wallpaper.backgroundColor = image == nil ? nil : fill.cgColor
        CATransaction.commit()
    }

    /// Swallow clicks rather than letting them fall through to the desktop.
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Square and as wide as the diagonal, so no corner ever shows as the
        // meshes turn.
        let side = (bounds.width * bounds.width + bounds.height * bounds.height).squareRoot() * 1.05
        for mesh in meshLayers {
            mesh.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            mesh.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        wallpaper.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - Gradient

/// What `prepare()` renders per wallpaper: the blur for one style and the
/// palette for the other, both from the same small decode.
private struct FogAssets {
    let blur: CGImage
    let palette: [CGColor]
}

/// The nine colours of the fog's 3×3 mesh, taken from the wallpaper.
private enum FogPalette {
    private typealias RGB = SIMD3<Double>

    /// The wallpaper's main colours (a small k-means), pushed up in
    /// saturation and contrast so the gradient reads as colour rather than
    /// mud. A near-single-colour wallpaper gets shades of that colour
    /// instead, so solid black becomes black and greys.
    static func make(from image: CGImage) -> [CGColor] {
        let side = 24
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: buffer.baseAddress, width: side, height: side,
                    bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return shades(of: RGB(0, 0, 0)) }

        let samples = stride(from: 0, to: bytes.count, by: 4).map {
            RGB(Double(bytes[$0]), Double(bytes[$0 + 1]), Double(bytes[$0 + 2])) / 255
        }
        let clusters = kMeans(samples, k: 5)
        let significant = clusters.filter { $0.share >= 0.05 }
        let spread = significant.flatMap { a in significant.map { b in distance(a.center, b.center) } }.max() ?? 0
        guard spread >= 0.15 else {
            return shades(of: clusters.first?.center ?? RGB(0, 0, 0))
        }
        let boosted = boost(significant.map(\.center))
        // Spread the colours over the mesh so neighbours differ.
        let order = [0, 1, 2, 3, 0, 4, 2, 1, 3]
        return order.map { color(boosted[$0 % boosted.count]) }
    }

    /// From a single colour (an unreadable wallpaper's fill colour, or none).
    static func make(from color: NSColor?) -> [CGColor] {
        guard let color else { return shades(of: RGB(0, 0, 0)) }
        return shades(of: RGB(Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)))
    }

    private static func shades(of base: RGB) -> [CGColor] {
        let (h, s0, v) = hsv(base)
        let s = min(1, s0 * 1.15)
        // Black lands on black and dark greys; a colour on its own darker
        // and lighter tones.
        let offsets: [Double] = [-0.10, 0.06, 0.16, 0.02, 0.24, -0.04, 0.12, 0.20, 0]
        return offsets.map { color(rgb(h, s, min(1, max(0, v + $0)))) }
    }

    private static func boost(_ colors: [RGB]) -> [RGB] {
        let values = colors.map { hsv($0) }
        let meanV = values.map(\.2).reduce(0, +) / Double(values.count)
        return values.map { h, s, v in
            let saturation = s < 0.08 ? s : min(1, s * 1.3 + 0.05)
            let value = min(1, max(0.04, meanV + (v - meanV) * 1.4))
            return rgb(h, saturation, value)
        }
    }

    // MARK: Clustering

    private struct Cluster { var center: RGB; var share: Double }

    /// Sorted largest first. Seeds are spread across the samples by
    /// brightness so a dark wallpaper's one bright accent still gets a seed.
    private static func kMeans(_ samples: [RGB], k: Int) -> [Cluster] {
        guard !samples.isEmpty else { return [] }
        let byBrightness = samples.sorted { $0.sum() < $1.sum() }
        var centers = (0..<k).map { byBrightness[($0 * (byBrightness.count - 1)) / max(k - 1, 1)] }
        var counts = [Int](repeating: 0, count: k)
        for _ in 0..<8 {
            var sums = [RGB](repeating: .zero, count: k)
            counts = [Int](repeating: 0, count: k)
            for sample in samples {
                let nearest = centers.indices.min { distance(sample, centers[$0]) < distance(sample, centers[$1]) }!
                sums[nearest] += sample
                counts[nearest] += 1
            }
            for i in centers.indices where counts[i] > 0 {
                centers[i] = sums[i] / Double(counts[i])
            }
        }
        return centers.indices
            .filter { counts[$0] > 0 }
            .map { Cluster(center: centers[$0], share: Double(counts[$0]) / Double(samples.count)) }
            .sorted { $0.share > $1.share }
    }

    private static func distance(_ a: RGB, _ b: RGB) -> Double {
        let d = a - b
        return (d * d).sum().squareRoot()
    }

    // MARK: Colour maths

    private static func color(_ c: RGB) -> CGColor {
        CGColor(srgbRed: c.x, green: c.y, blue: c.z, alpha: 1)
    }

    private static func hsv(_ c: RGB) -> (Double, Double, Double) {
        let maxC = max(c.x, c.y, c.z), minC = min(c.x, c.y, c.z), delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == c.x { h = ((c.y - c.z) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == c.y { h = (c.z - c.x) / delta + 2 }
            else { h = (c.x - c.y) / delta + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, maxC == 0 ? 0 : delta / maxC, maxC)
    }

    private static func rgb(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return RGB(v, t, p)
        case 1: return RGB(q, v, p)
        case 2: return RGB(p, v, t)
        case 3: return RGB(p, q, v)
        case 4: return RGB(t, p, v)
        default: return RGB(v, p, q)
        }
    }
}

/// Renders the palette as a still 3×3 mesh image. Small, because it is
/// smooth by nature and Core Animation scales it up for free.
private enum FogMeshImage {
    private static let side: CGFloat = 512

    /// Inner points pushed off-centre so the mesh looks organic rather than
    /// like a grid of nine tiles.
    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.62, 0], [1, 0],
        [0, 0.38], [0.42, 0.6], [1, 0.55],
        [0, 1], [0.35, 1], [1, 1],
    ]

    static func render(_ palette: [CGColor]) -> CGImage? {
        let colors = palette.count == 9
            ? palette.map { Color(cgColor: $0) }
            : Array(repeating: Color.black, count: 9)
        let renderer = ImageRenderer(
            content: MeshGradient(width: 3, height: 3, points: points, colors: colors, smoothsColors: true)
                .frame(width: side, height: side)
        )
        renderer.scale = 1
        return renderer.cgImage
    }
}
