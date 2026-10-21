import AppKit
import AVFoundation
import SwiftUI
import CoreImage
import ImageIO
import Metal
import MetalKit
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

    /// Fully opaque. 0.99 was tried, to keep the desktop from counting as
    /// occluded, but compositing is in linear light, so 1% of white text over
    /// a dark fog comes out around 10% grey and the windows behind showed
    /// through. The occlusion is handled by `fogFrame(for:)` instead.
    private let shownAlpha: CGFloat = 1

    /// The exit's first step. While the fog is fully opaque the windows behind
    /// it count as occluded, and apps that drop their content when occluded
    /// (browsers, Electron, video) only redraw once they are uncovered. The
    /// top-row gap in `fogFrame(for:)` only keeps windows that reach the menu
    /// bar visible, so everything else came back black for the first part of
    /// the fade. Dropping just under opaque first un-occludes them while the
    /// fog still hides them, and they redraw during `revealLeadTime`.
    ///
    /// The worst case is an app activated while the fog was up: its windows
    /// came forward fully covered and were never drawn at all, and 0.05s was
    /// not enough for them. A still hold that long read as lag, though, so
    /// the fog starts lifting visibly (`FogView.beginLift`) the moment the
    /// exit begins, and the hold hides inside that motion.
    private let revealAlpha: CGFloat = 0.97
    private let revealLeadTime: TimeInterval = 0.15

    /// The screen minus its top point, which sits behind the menu bar. A
    /// window covering the *whole* screen occludes the desktop, macOS drops
    /// the wallpaper underneath, and the first fade out showed black until it
    /// redrew. One uncovered row keeps the desktop counted as visible.
    private static func fogFrame(for screen: NSScreen) -> NSRect {
        var frame = screen.frame
        frame.size.height -= 1
        return frame
    }

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
        // Compiles the gradient's shader off the main thread, so the first
        // shake in Gradient style doesn't wait on it.
        DispatchQueue.global(qos: .utility).async { _ = FogMeshRenderer.shared }
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

    /// Every exit takes this path, including hiding the panel and quitting.
    /// There is no instant drop: removing the fog in one frame showed every
    /// covered window black until its app redrew. `completion` runs once the
    /// fog is gone (or a new show has taken the windows over).
    func hide(completion: (() -> Void)? = nil) {
        guard isActive else {
            completion?()
            return
        }
        isActive = false
        generation += 1
        let expected = generation
        for window in windows {
            window.alphaValue = revealAlpha
            (window.contentView as? FogView)?.beginLift(duration: revealLeadTime + fadeOutDuration)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + revealLeadTime) { [weak self] in
            // A show that landed during the lead-in owns the windows now.
            guard let self, self.generation == expected else {
                completion?()
                return
            }
            self.fade(to: 0, duration: self.fadeOutDuration, timing: .easeIn) { [weak self] in
                defer { completion?() }
                // Likewise for one that landed mid-fade.
                guard let self, self.generation == expected else { return }
                self.windows.forEach(self.retire)
                self.prepare()
            }
        }
    }

    // MARK: - Windows

    /// Ordered out, with the gradient's display link stopped so nothing keeps
    /// rendering while the fog is down.
    private func retire(_ window: NSWindow) {
        window.orderOut(nil)
        (window.contentView as? FogView)?.stopAnimating()
        (window.contentView as? FogView)?.endLift()
    }

    private func applyContent(to window: NSWindow, screen: NSScreen) {
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let assets = fogAssets[WallpaperKey(screen: screen)]
        // An unreadable wallpaper still gets a gradient, from its fill colour.
        let palette = assets?.palette
            ?? FogPalette.make(from: (options[.fillColor] as? NSColor)?.usingColorSpace(.sRGB))
        (window.contentView as? FogView)?.apply(
            image: assets?.blur,
            artwork: assets?.artwork,
            palette: palette,
            style: style,
            options: options
        )
    }

    private func present(animated: Bool) {
        for (window, screen) in zip(windows, NSScreen.screens) {
            window.setFrame(Self.fogFrame(for: screen), display: false)
            // A show that interrupted an exit takes over a lifting window.
            (window.contentView as? FogView)?.endLift()
            window.alphaValue = animated ? 0 : shownAlpha
            // On screen before the content goes in, so the gradient's display
            // link starts on the display it will run on.
            window.orderFront(nil)
            applyContent(to: window, screen: screen)
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
                contentRect: Self.fogFrame(for: screen),
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
            window.contentView = FogView(frame: NSRect(origin: .zero, size: Self.fogFrame(for: screen).size))
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
        let analysis = FogPalette.analyze(thumbnail)
        return FogAssets(
            blur: blur,
            palette: analysis.palette,
            // A near-single-colour wallpaper has nothing to swirl; the
            // gradient uses its shades instead.
            artwork: analysis.isVaried ? FogArtwork.make(from: thumbnail) : nil
        )
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

/// The fog's content. Wallpaper Blur: just the blurred wallpaper, with no
/// tint or mist on top (anything layered over it read as a white wash).
/// Without a readable wallpaper it falls back to a live backdrop blur.
/// Gradient: a `FogMeshView`.
private final class FogView: NSView {
    private let fallbackBlur = NSVisualEffectView()
    /// Its own subview, so AppKit can't slide the layer under the blur.
    private let overlay = NSView()
    private let wallpaper = CALayer()
    private let mesh = FogMeshView()

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

        mesh.frame = bounds
        mesh.autoresizingMask = [.width, .height]
        mesh.isHidden = true
        addSubview(mesh)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(
        image: CGImage?,
        artwork: CGImage?,
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
            mesh.isHidden = false
            // A plain or unreadable wallpaper moves its own shades instead.
            mesh.setArtwork(artwork ?? FogMeshImage.render(palette))
            mesh.startAnimating()
        }
    }

    /// Stops the gradient while the fog is down; it restarts on the next
    /// `apply`.
    func stopAnimating() {
        mesh.stopAnimating()
        mesh.isHidden = true
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

    /// The exit's motion: the fog zooms in slightly as it lifts, starting the
    /// moment the exit does, so the opaque hold in `hide` reads as the fog
    /// already moving rather than as a delay. A fill-forwards animation
    /// rather than a model change, so AppKit's own layer geometry is left
    /// alone; `endLift` takes it off. Skipped under Reduce Motion.
    func beginLift(duration: TimeInterval) {
        guard let layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        // About the centre, whatever anchor AppKit gave the backing layer.
        let pivot = CGPoint(
            x: (0.5 - layer.anchorPoint.x) * bounds.width,
            y: (0.5 - layer.anchorPoint.y) * bounds.height
        )
        var lifted = CATransform3DMakeTranslation(pivot.x, pivot.y, 0)
        lifted = CATransform3DScale(lifted, 1.06, 1.06, 1)
        lifted = CATransform3DTranslate(lifted, -pivot.x, -pivot.y, 0)
        let lift = CABasicAnimation(keyPath: "transform")
        lift.fromValue = CATransform3DIdentity
        lift.toValue = lifted
        lift.duration = duration
        lift.timingFunction = CAMediaTimingFunction(name: .easeOut)
        lift.fillMode = .forwards
        lift.isRemovedOnCompletion = false
        layer.add(lift, forKey: "lift")
    }

    func endLift() {
        layer?.removeAnimation(forKey: "lift")
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
        wallpaper.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - Moving mesh

/// The gradient, done the way Apple Music's lyrics backdrop does it now (as
/// reverse-engineered by the Apple Music-like Lyrics project's mesh
/// renderer): the processed artwork is stretched over a mesh whose control
/// points each drift on their own slow path, so the colour fields flow and
/// fold into each other with no shape of their own.
///
/// It replaced four copies of the artwork spinning at different speeds, the
/// smaller ones feathered to circles and orbiting. That was Apple Music's
/// *older* renderer, and the circles read as balls moving around the screen.
///
/// Metal rather than Core Animation, because CA has no public mesh warp. The
/// drawable is one pixel per point (the image is a blur, so Retina detail
/// is wasted) and the shader is a texture sample per pixel, so it is cheap.
/// The display link is the view's own, so it runs while the fog window is
/// on screen whether or not Buoy is active; a SwiftUI `TimelineView` here
/// rendered once and stopped.
private final class FogMeshView: NSView {
    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }
    private var texture: MTLTexture?
    private var displayLink: CADisplayLink?
    /// Each show starts somewhere new in the motion rather than replaying
    /// the same opening.
    private var timeOrigin: CFTimeInterval = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { displayLink?.invalidate() }

    override func makeBackingLayer() -> CALayer {
        guard let renderer = FogMeshRenderer.shared else {
            // No Metal: the artwork as a still image, which is still the
            // right colours.
            let still = CALayer()
            still.contentsGravity = .resizeAspectFill
            return still
        }
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        // The texture holds sRGB-encoded values and the shader passes them
        // straight through, so tag the output the same way.
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.framebufferOnly = true
        layer.isOpaque = true
        layer.contentsGravity = .resize
        return layer
    }

    func setArtwork(_ image: CGImage?) {
        guard let image else { texture = nil; return }
        guard let renderer = FogMeshRenderer.shared else {
            layer?.contents = image
            return
        }
        texture = renderer.texture(from: image)
        render(time: currentTime)
    }

    func startAnimating() {
        displayLink?.invalidate()
        displayLink = nil
        timeOrigin = CACurrentMediaTime() - Double.random(in: 0..<600)
        render(time: currentTime)
        // Reduce Motion keeps the gradient but holds it still.
        guard FogMeshRenderer.shared != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopAnimating() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private var currentTime: CFTimeInterval { CACurrentMediaTime() - timeOrigin }

    @objc private func step(_ link: CADisplayLink) {
        render(time: link.targetTimestamp - timeOrigin)
    }

    override func layout() {
        super.layout()
        guard let metalLayer else { return }
        let size = CGSize(width: max(1, bounds.width.rounded()), height: max(1, bounds.height.rounded()))
        if metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
            render(time: currentTime)
        }
    }

    private func render(time: CFTimeInterval) {
        guard let metalLayer, let texture, let renderer = FogMeshRenderer.shared,
              bounds.width > 0, bounds.height > 0
        else { return }
        renderer.draw(
            into: metalLayer,
            artwork: texture,
            // Wrapped so the float the shader gets never loses precision
            // after the fog has been up for hours. Every speed in the shader
            // is a multiple of 2π / 3600 s, so the wrap is seamless.
            time: Float(time.truncatingRemainder(dividingBy: 3600)),
            aspect: Float(bounds.width / bounds.height)
        )
    }
}

/// The Metal side of `FogMeshView`, built once and shared by every screen.
private final class FogMeshRenderer {
    static let shared = FogMeshRenderer()

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let loader: MTKTextureLoader

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shaderSource, options: nil),
              let vertex = library.makeFunction(name: "fogMeshVertex"),
              let fragment = library.makeFunction(name: "fogMeshFragment")
        else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.loader = MTKTextureLoader(device: device)
    }

    func texture(from image: CGImage) -> MTLTexture? {
        try? loader.newTexture(cgImage: image, options: [
            // Keep the sRGB-encoded bytes as they are; see `makeBackingLayer`.
            .SRGB: false,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
        ])
    }

    private struct Uniforms {
        var time: Float
        var aspect: Float
    }

    func draw(into layer: CAMetalLayer, artwork: MTLTexture, time: Float, aspect: Float) {
        guard let drawable = layer.nextDrawable(),
              let commands = queue.makeCommandBuffer()
        else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = Uniforms(time: time, aspect: aspect)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(artwork, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    /// Compiled at runtime so the fog stays one self-contained file.
    ///
    /// The mesh: a 5×5 grid of control points over the screen, each drifting
    /// on its own ellipse (speed and phase hashed from its cell), blended
    /// with Catmull-Rom so the warp is smooth everywhere. The artwork is
    /// sampled through two layers of it, the second warping the first's
    /// result, which turns drift into the slow folding Apple Music has. A
    /// gentle sway of the whole image keeps the big fields travelling.
    /// Amplitudes stay under the grid spacing so the mesh never folds over
    /// itself into a visible crease. Last, a sub-step dither (under 1/255,
    /// so not grain) keeps the smooth ramps from banding on a large screen.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    struct Uniforms {
        float time;
        float aspect;
    };

    vertex VertexOut fogMeshVertex(uint id [[vertex_id]]) {
        // One triangle that covers the screen.
        float2 corner = float2(float((id << 1) & 2), float(id & 2));
        VertexOut out;
        out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
        out.uv = float2(corner.x, 1.0 - corner.y);
        return out;
    }

    static float hash(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    }

    // Each point loops in 7–11 s, close to Apple Music's pace (24–40 s read
    // as sluggish). Every speed is a whole multiple of
    // 2π / 3600 s, so wrapping time at 3600 s is seamless.
    constant float kStep = 6.2831853 / 3600.0;

    static float2 controlOffset(int2 cell, float t) {
        float2 c = float2(cell);
        float phaseX = hash(c) * 6.2831853;
        float phaseY = hash(c + 17.0) * 6.2831853;
        float speedX = kStep * floor(330.0 + 180.0 * hash(c + 31.0));
        float speedY = kStep * floor(330.0 + 180.0 * hash(c + 47.0));
        return float2(sin(t * speedX + phaseX), cos(t * speedY + phaseY));
    }

    static float2 catmullRom(float2 p0, float2 p1, float2 p2, float2 p3, float x) {
        float x2 = x * x, x3 = x2 * x;
        return 0.5 * (2.0 * p1
                      + (p2 - p0) * x
                      + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * x2
                      + (3.0 * p1 - p0 - 3.0 * p2 + p3) * x3);
    }

    static float2 meshDisplacement(float2 uv, float t) {
        float2 g = uv * 4.0;
        int2 base = int2(floor(g));
        float2 f = g - floor(g);
        float2 rows[4];
        for (int j = 0; j < 4; j++) {
            float2 p0 = controlOffset(base + int2(-1, j - 1), t);
            float2 p1 = controlOffset(base + int2( 0, j - 1), t);
            float2 p2 = controlOffset(base + int2( 1, j - 1), t);
            float2 p3 = controlOffset(base + int2( 2, j - 1), t);
            rows[j] = catmullRom(p0, p1, p2, p3, f.x);
        }
        return catmullRom(rows[0], rows[1], rows[2], rows[3], f.y);
    }

    fragment float4 fogMeshFragment(VertexOut in [[stage_in]],
                                    constant Uniforms &u [[buffer(0)]],
                                    texture2d<float> artwork [[texture(0)]]) {
        constexpr sampler smooth(filter::linear, address::mirrored_repeat);
        float t = u.time;

        float2 uv = in.uv;
        uv += 0.075 * meshDisplacement(uv, t);
        uv += 0.04 * meshDisplacement(uv + 0.37, t);

        // Aspect-fill the square artwork, zoomed in so the warp and sway
        // rarely reach its edge (and mirror smoothly when they do).
        float2 q = uv - 0.5;
        q *= u.aspect >= 1.0 ? float2(1.0, 1.0 / u.aspect) : float2(u.aspect, 1.0);
        float angle = 0.3 * sin(t * kStep * 80.0);
        float2 drift = 0.05 * float2(sin(t * kStep * 100.0), cos(t * kStep * 75.0));
        q = float2x2(cos(angle), sin(angle), -sin(angle), cos(angle)) * q + drift;
        float3 color = artwork.sample(smooth, 0.5 + q * 0.78).rgb;

        color += (hash(in.position.xy + fract(t)) - 0.5) / 255.0;
        return float4(color, 1.0);
    }
    """
}

// MARK: - Gradient

/// What `prepare()` renders per wallpaper: the blur for one style and the
/// palette for the other, both from the same small decode.
private struct FogAssets {
    let blur: CGImage
    let palette: [CGColor]
    /// The gradient's source image; `nil` for a near-single-colour wallpaper.
    let artwork: CGImage?
}

/// The wallpaper prepared for the gradient: shrunk to 32 px (which turns a
/// photo into a few big fields of colour, as Apple Music does with album
/// art), then levelled so any wallpaper comes out vivid. Brightness is
/// stretched from the image's own 5th–95th percentile onto 0.32–0.92, and
/// saturation is scaled until its 90th percentile reaches 0.9 (gain capped
/// at 6×). Hue is untouched, so the colours are still the wallpaper's.
///
/// Apple Music's fixed recipe (contrast 0.4 → saturation 3 → contrast 1.7 →
/// brightness 0.75) was tried first: it suits bright album art, but on a
/// night wallpaper it collapsed to near-black grey.
private enum FogArtwork {
    private static let side = 32
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func make(from image: CGImage) -> CGImage? {
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
        guard drew else { return nil }

        let pixels = stride(from: 0, to: bytes.count, by: 4).map {
            FogPalette.hsv(SIMD3(Double(bytes[$0]), Double(bytes[$0 + 1]), Double(bytes[$0 + 2])) / 255)
        }
        func percentile(_ values: [Double], _ fraction: Double) -> Double {
            let sorted = values.sorted()
            return sorted[Int(Double(sorted.count - 1) * fraction)]
        }
        let values = pixels.map(\.2), saturations = pixels.map(\.1)
        let low = percentile(values, 0.05), high = percentile(values, 0.95)
        let gain = min(6, max(1, 0.9 / max(percentile(saturations, 0.9), 0.05)))

        for (index, (hue, saturation, value)) in pixels.enumerated() {
            let level = high - low > 0.01 ? min(1, max(0, (value - low) / (high - low))) : 0.5
            let color = FogPalette.rgb(hue, min(1, saturation * gain), 0.32 + 0.6 * level)
            bytes[index * 4] = UInt8(color.x * 255)
            bytes[index * 4 + 1] = UInt8(color.y * 255)
            bytes[index * 4 + 2] = UInt8(color.z * 255)
            bytes[index * 4 + 3] = 255
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let small = CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: side * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { return nil }

        // Upscaled and blurred here, once, so the layers stretching it to
        // screen size show smooth fields rather than bilinear creases.
        let input = CIImage(cgImage: small)
        let large = input
            .clampedToExtent()
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 8])
            .applyingGaussianBlur(sigma: 14)
            .cropped(to: CGRect(x: 0, y: 0, width: side * 8, height: side * 8))
        return context.createCGImage(large, from: large.extent)
    }
}

/// The nine colours of the fog's 3×3 mesh, taken from the wallpaper.
private enum FogPalette {
    private typealias RGB = SIMD3<Double>

    /// The wallpaper's main colours (a small k-means), pushed up in
    /// saturation and contrast so the gradient reads as colour rather than
    /// mud. A near-single-colour wallpaper gets shades of that colour
    /// instead, so solid black becomes black and greys.
    /// The palette, and whether the wallpaper has enough colour variety to
    /// be worth using as gradient artwork.
    static func analyze(_ image: CGImage) -> (palette: [CGColor], isVaried: Bool) {
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
        guard drew else { return (shades(of: RGB(0, 0, 0)), false) }

        let samples = stride(from: 0, to: bytes.count, by: 4).map {
            RGB(Double(bytes[$0]), Double(bytes[$0 + 1]), Double(bytes[$0 + 2])) / 255
        }
        let clusters = kMeans(samples, k: 5)
        let significant = clusters.filter { $0.share >= 0.05 }
        let spread = significant.flatMap { a in significant.map { b in distance(a.center, b.center) } }.max() ?? 0
        guard spread >= 0.10 else {
            return (shades(of: clusters.first?.center ?? RGB(0, 0, 0)), false)
        }
        let boosted = boost(significant.map(\.center))
        // Spread the colours over the mesh so neighbours differ.
        let order = [0, 1, 2, 3, 0, 4, 2, 1, 3]
        return (order.map { color(boosted[$0 % boosted.count]) }, true)
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
        let offsets: [Double] = [-0.10, 0.10, 0.24, 0.04, 0.36, -0.04, 0.18, 0.30, 0]
        return offsets.map { color(rgb(h, s, min(1, max(0, v + $0)))) }
    }

    private static func boost(_ colors: [RGB]) -> [RGB] {
        let values = colors.map { hsv($0) }
        let meanV = values.map(\.2).reduce(0, +) / Double(values.count)
        return values.map { h, s, v in
            let saturation = s < 0.08 ? s : min(1, s * 1.3 + 0.05)
            // Floored so a night wallpaper still has visible colour to move.
            let value = min(1, max(0.24, meanV + (v - meanV) * 1.4))
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

    static func hsv(_ c: SIMD3<Double>) -> (Double, Double, Double) {
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

    static func rgb(_ h: Double, _ s: Double, _ v: Double) -> SIMD3<Double> {
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
