import AppKit
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Focus fog: covers the rest of the desktop with a heavily blurred copy of
/// the user's own wallpaper, so the note is the only sharp thing on screen.
/// Toggled by shaking the header (see `DragEnablingNSView`), owned by
/// `AppDelegate`.
///
/// One click-through borderless window per screen, sitting just *below* the
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
    private var fogImages: [WallpaperKey: CGImage] = [:]
    private var rendering: Set<WallpaperKey> = []
    private var renderCallbacks: [() -> Void] = []
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var generation = 0

    /// Ease-out so the fog is visibly moving from the first frame; an
    /// ease-in-out start reads as a delay.
    private let fadeInDuration: TimeInterval = 0.55
    private let fadeOutDuration: TimeInterval = 0.4

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
            .filter { fogImages[$0] == nil && !rendering.contains($0) }
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
                for (key, image) in rendered {
                    self.rendering.remove(key)
                    if let image { self.fogImages[key] = image }
                }
                guard self.rendering.isEmpty else { return }
                let callbacks = self.renderCallbacks
                self.renderCallbacks.removeAll()
                callbacks.forEach { $0() }
            }
        }
    }

    func show() {
        guard !isActive else { return }
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

    func hide(animated: Bool = true) {
        guard isActive else { return }
        isActive = false
        generation += 1
        guard animated else {
            windows.forEach { $0.orderOut(nil) }
            prepare()
            return
        }
        let expected = generation
        fade(to: 0, duration: fadeOutDuration, timing: .easeIn) { [weak self] in
            // A show that landed mid-fade owns the windows now.
            guard let self, self.generation == expected else { return }
            self.windows.forEach { $0.orderOut(nil) }
            self.prepare()
        }
    }

    // MARK: - Windows

    private func present(animated: Bool) {
        for (window, screen) in zip(windows, NSScreen.screens) {
            window.setFrame(screen.frame, display: false)
            let key = WallpaperKey(screen: screen)
            (window.contentView as? FogView)?.apply(
                image: fogImages[key],
                options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            )
            window.alphaValue = animated ? 0 : 1
            window.orderFront(nil)
        }
        guard animated else { return }
        // Let the order-in reach the window server before the fade starts, so
        // its first frames aren't spent on that commit.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive else { return }
            self.fade(to: 1, duration: self.fadeInDuration, timing: .easeOut)
        }
    }

    private func buildWindows() {
        tearDownWindows()
        windows = NSScreen.screens.map { screen in
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
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
    static func render(_ key: WallpaperKey) -> CGImage? {
        guard let url = key.url,
              let thumbnail = stillFrame(of: url, index: key.frameIndex) ?? videoFrame(of: url)
        else { return nil }

        let input = CIImage(cgImage: thumbnail)
        let fog = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: blurSigma)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.15])
            .cropped(to: input.extent)
        return context.createCGImage(fog, from: input.extent)
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

// MARK: - View

/// The blurred wallpaper, a soft veil, and a few slow-drifting mist clouds.
/// The clouds are `CAGradientLayer`s moved by `CABasicAnimation`, so the drift
/// is composited on the GPU rather than redrawn each frame. Without a readable
/// wallpaper it falls back to a live backdrop blur.
private final class FogView: NSView {
    private struct Cloud {
        let center: CGPoint      // fraction of the view
        let radius: CGFloat      // fraction of the longer side
        let drift: CGSize        // fraction of the view, travelled and back
        let duration: CFTimeInterval
        let opacity: Float
    }

    private static let clouds: [Cloud] = [
        Cloud(center: CGPoint(x: 0.18, y: 0.72), radius: 0.46, drift: CGSize(width: 0.14, height: 0.05), duration: 26, opacity: 0.9),
        Cloud(center: CGPoint(x: 0.78, y: 0.80), radius: 0.40, drift: CGSize(width: -0.12, height: 0.07), duration: 31, opacity: 0.8),
        Cloud(center: CGPoint(x: 0.52, y: 0.46), radius: 0.52, drift: CGSize(width: 0.10, height: -0.06), duration: 37, opacity: 0.7),
        Cloud(center: CGPoint(x: 0.12, y: 0.22), radius: 0.38, drift: CGSize(width: 0.16, height: 0.08), duration: 29, opacity: 0.85),
        Cloud(center: CGPoint(x: 0.86, y: 0.26), radius: 0.44, drift: CGSize(width: -0.15, height: -0.04), duration: 34, opacity: 0.8),
    ]

    private let fallbackBlur = NSVisualEffectView()
    /// Its own subview, so AppKit can't slide the layers under the blur.
    private let overlay = NSView()
    private let wallpaper = CALayer()
    private let veil = CALayer()
    private let cloudContainer = CALayer()
    private var cloudLayers: [CAGradientLayer] = []

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
        overlay.layer?.addSublayer(veil)
        overlay.layer?.addSublayer(cloudContainer)
        for _ in Self.clouds {
            let cloud = CAGradientLayer()
            cloud.type = .radial
            cloud.startPoint = CGPoint(x: 0.5, y: 0.5)
            cloud.endPoint = CGPoint(x: 1, y: 1)
            cloud.locations = [0, 1]
            cloudContainer.addSublayer(cloud)
            cloudLayers.append(cloud)
        }
        refreshColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Lays the fog out the way the desktop lays out the wallpaper.
    func apply(image: CGImage?, options: [NSWorkspace.DesktopImageOptionKey: Any]) {
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wallpaper.frame = bounds
        veil.frame = bounds
        cloudContainer.frame = bounds
        CATransaction.commit()

        let longSide = max(bounds.width, bounds.height)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        for (cloud, spec) in zip(cloudLayers, Self.clouds) {
            let diameter = longSide * spec.radius * 2
            cloud.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            let origin = CGPoint(x: bounds.width * spec.center.x, y: bounds.height * spec.center.y)
            cloud.position = origin
            cloud.opacity = spec.opacity

            cloud.removeAllAnimations()
            guard !reduceMotion else { continue }
            let drift = CABasicAnimation(keyPath: "position")
            drift.fromValue = origin
            drift.toValue = CGPoint(
                x: origin.x + bounds.width * spec.drift.width,
                y: origin.y + bounds.height * spec.drift.height
            )
            drift.duration = spec.duration
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cloud.add(drift, forKey: "drift")
        }
    }

    /// The veil and mist are white so they take the wallpaper's own colour;
    /// dark mode keeps them faint and dims slightly instead, or a night
    /// wallpaper would wash out to grey.
    private func refreshColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let veilColor: NSColor = isDark
            ? NSColor(white: 0, alpha: 0.12)
            : NSColor(white: 1, alpha: 0.16)
        let mist: NSColor = isDark
            ? NSColor(white: 1, alpha: 0.10)
            : NSColor(white: 1, alpha: 0.32)

        veil.backgroundColor = veilColor.cgColor
        for cloud in cloudLayers {
            cloud.colors = [mist.cgColor, mist.withAlphaComponent(0).cgColor]
        }
    }
}
