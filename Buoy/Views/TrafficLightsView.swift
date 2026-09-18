import SwiftUI
import AppKit
import QuartzCore

/// The panel's traffic lights, drawn by AppKit itself.
///
/// Buoy's panel is borderless, so it has no titlebar to inherit window buttons
/// from. Instead of hand-drawing circles, this hosts the *real* buttons AppKit
/// vends via `NSWindow.standardWindowButton(_:for:)`, which gives us the system
/// gradients, glyphs, pressed/inactive states, Reduce Transparency and
/// Increase Contrast treatments, and accessibility roles for free.
struct TrafficLightsView: NSViewRepresentable {
    var onClose: () -> Void
    var onMinimize: () -> Void
    var onExpand: () -> Void
    /// Compact chrome's size reduction. These are real AppKit window buttons
    /// with no smaller variant to ask for, so the group scales its own
    /// coordinate system instead of its subviews' frames.
    var scale: CGFloat = 1

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose, onMinimize: onMinimize, onExpand: onExpand)
    }

    func makeNSView(context: Context) -> TrafficLightGroupView {
        let view = TrafficLightGroupView(coordinator: context.coordinator)
        view.scale = scale
        return view
    }

    func updateNSView(_ nsView: TrafficLightGroupView, context: Context) {
        context.coordinator.onClose = onClose
        context.coordinator.onMinimize = onMinimize
        context.coordinator.onExpand = onExpand
        nsView.scale = scale
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TrafficLightGroupView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    final class Coordinator: NSObject {
        var onClose: () -> Void
        var onMinimize: () -> Void
        var onExpand: () -> Void

        init(onClose: @escaping () -> Void, onMinimize: @escaping () -> Void, onExpand: @escaping () -> Void) {
            self.onClose = onClose
            self.onMinimize = onMinimize
            self.onExpand = onExpand
        }

        @objc func close(_ sender: Any?) { onClose() }
        @objc func minimize(_ sender: Any?) { onMinimize() }
        @objc func expand(_ sender: Any?) { onExpand() }
    }
}

/// Container that lays the three standard window buttons out on the native pitch
/// and drives their group-hover state.
final class TrafficLightGroupView: NSView {
    /// Horizontal distance between button origins, measured from a real titlebar
    /// rather than hardcoded — AppKit widened it from 20pt to 23pt in the macOS 26
    /// line, and a stale value reads as visibly cramped lights.
    private static let buttonPitch: CGFloat = {
        let probe = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        probe.isReleasedWhenClosed = false
        guard let close = probe.standardWindowButton(.closeButton),
              let zoom = probe.standardWindowButton(.zoomButton),
              zoom.frame.minX > close.frame.minX else { return 23 }
        return (zoom.frame.minX - close.frame.minX) / 2
    }()

    /// A window widget caches its rendering in a layer, so `needsDisplay` alone
    /// never re-asks `_mouseInGroup:` — the glyphs would freeze at whatever they
    /// were on first draw. This is the hook AppKit's own titlebar pokes to make a
    /// widget re-evaluate its hover state and repaint.
    private static let repaintSelector = Selector(("mouseEnteredOrExited"))

    /// The group currently on screen, if any. `CornerResizeOverlayController`
    /// reads this to keep its top-leading arc from covering the lights.
    private static weak var liveGroup: TrafficLightGroupView?

    /// Screen-space frame of the on-screen group, optionally padded.
    static func screenFrame(padding: CGFloat = 0) -> NSRect? {
        liveGroup?.currentScreenFrame?.insetBy(dx: -padding, dy: -padding)
    }

    /// How long the colored/graphite crossfade runs when the panel takes or
    /// loses key. Matches the titlebar's own activation fade closely enough that
    /// Buoy's lights and a neighbouring window's settle together.
    private static let activeStateFadeDuration: CFTimeInterval = 0.25

    private var buttons: [NSButton] = []
    private var isMouseInGroup = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var keyStateObservers: [NSObjectProtocol] = []

    init(coordinator: TrafficLightsView.Coordinator) {
        super.init(frame: .zero)

        // The style mask only describes which buttons to vend; these are
        // detached buttons, unrelated to the panel's own (borderless) mask.
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let specs: [(NSWindow.ButtonType, Selector)] = [
            (.closeButton, #selector(TrafficLightsView.Coordinator.close(_:))),
            (.miniaturizeButton, #selector(TrafficLightsView.Coordinator.minimize(_:))),
            (.zoomButton, #selector(TrafficLightsView.Coordinator.expand(_:)))
        ]

        for (index, spec) in specs.enumerated() {
            guard let button = NSWindow.standardWindowButton(spec.0, for: styleMask) else { continue }
            button.target = coordinator
            button.action = spec.1
            button.isEnabled = true
            button.setFrameOrigin(NSPoint(x: CGFloat(index) * Self.buttonPitch, y: 0))
            addSubview(button)
            buttons.append(button)
        }

        setFrameSize(intrinsicContentSize)
    }

    deinit {
        removeMouseMonitors()
        removeKeyStateObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shrinks the group without touching the buttons.
    ///
    /// Done by keeping `bounds` at the buttons' natural size while `frame`
    /// takes the scaled one. That is a genuine coordinate transform, so
    /// AppKit's own hit testing, cursor rects and coordinate conversions all
    /// follow it — which a `layer.transform` or a SwiftUI `scaleEffect` would
    /// not, leaving the lights drawn in one place and clickable in another.
    var scale: CGFloat = 1 {
        didSet {
            guard scale != oldValue, scale > 0 else { return }
            applyScale()
        }
    }

    override var intrinsicContentSize: NSSize {
        let natural = buttonsRect.size
        return NSSize(width: natural.width * scale, height: natural.height * scale)
    }

    private func applyScale() {
        invalidateIntrinsicContentSize()
        // `setFrameSize` below re-asserts the bounds for the new scale.
        setFrameSize(intrinsicContentSize)
        needsLayout = true
        needsDisplay = true
    }

    /// Keeps `bounds` at the buttons' natural size whatever frame SwiftUI
    /// hands this view, which is what makes the scale a coordinate transform
    /// rather than a redraw.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        setBoundsSize(NSSize(width: newSize.width / scale, height: newSize.height / scale))
    }

    /// Union of the buttons themselves rather than `bounds`, so hover testing
    /// stays correct even if SwiftUI hands the container a different size.
    private var buttonsRect: NSRect {
        buttons.reduce(.null) { $0.union($1.frame) }
    }

    // A titlebar answers this for its own window buttons; the standard button
    // cells ask their superview for it to decide whether to draw the ×, − and +
    // glyphs. Implementing it here makes all three light up together on hover,
    // exactly like a real titlebar.
    @objc func _mouseInGroup(_ button: NSButton) -> Bool { isMouseInGroup }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeKeyStateObservers()
        if let window {
            Self.liveGroup = self
            // Don't rely on the corner-resize controller having set this.
            window.acceptsMouseMovedEvents = true
            installMouseMonitors()
            installKeyStateObservers(for: window)
        } else {
            removeMouseMonitors()
        }
        syncMouseInGroupWithPointer()
    }

    // MARK: - Hover tracking
    //
    // Two independent event sources feed one idempotent recompute. Buoy's panel
    // is a non-activating floating panel, where tracking-area enter/exit is not
    // dependable on its own; the monitors are what `CornerResizeOverlayController`
    // already relies on for the same reason. Because the recompute always derives
    // state from the pointer's real position, a missed or spurious event from
    // either source is self-correcting rather than leaving a glyph stuck on.

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
        syncMouseInGroupWithPointer()
    }

    override func mouseEntered(with event: NSEvent) { syncMouseInGroupWithPointer() }

    override func mouseExited(with event: NSEvent) { syncMouseInGroupWithPointer() }

    override func mouseMoved(with event: NSEvent) { syncMouseInGroupWithPointer() }

    private func installMouseMonitors() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.syncMouseInGroupWithPointer()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.syncMouseInGroupWithPointer()
        }
    }

    private func removeMouseMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    /// The buttons' own frame in screen space, or nil when off screen.
    fileprivate var currentScreenFrame: NSRect? {
        let rect = buttonsRect
        guard let window, window.isVisible, !rect.isEmpty else { return nil }
        return window.convertToScreen(convert(rect, to: nil))
    }

    private func syncMouseInGroupWithPointer() {
        guard let frame = currentScreenFrame else {
            setMouseInGroup(false)
            return
        }
        setMouseInGroup(frame.contains(NSEvent.mouseLocation))
    }

    private func setMouseInGroup(_ inside: Bool) {
        guard isMouseInGroup != inside else { return }
        isMouseInGroup = inside
        buttons.forEach(repaint)
    }

    private func repaint(_ button: NSButton) {
        if button.responds(to: Self.repaintSelector) {
            _ = button.perform(Self.repaintSelector)
        } else {
            // Wrong glyphs beat a crash if AppKit ever renames that hook.
            button.needsDisplay = true
        }
    }

    // MARK: - Activation crossfade
    //
    // A real titlebar crossfades its lights between the colored and graphite
    // renderings as the window takes and loses key. These are detached widgets:
    // AppKit still restates them on a key change (`_windowChangedKeyState` marks
    // the control dirty), but with nothing driving an animation the swap lands as
    // a hard cut, which reads as a flicker next to any native window.
    //
    // The fix rides the widget's own layer caching rather than fighting it. The
    // repaint doesn't happen when `needsDisplay` is set — it happens in the
    // display pass at the end of the runloop iteration. Notifications are
    // delivered before that pass, so a `CATransition` attached here is already in
    // place when the layer's contents are replaced, and Core Animation crossfades
    // the old rendering into the new one for free.

    private func installKeyStateObservers(for window: NSWindow) {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyStateObservers.append(
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.crossfadeActiveState()
                }
            )
        }
    }

    private func removeKeyStateObservers() {
        for observer in keyStateObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        keyStateObservers.removeAll()
    }

    private func crossfadeActiveState() {
        for button in buttons {
            if let layer = button.layer {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = Self.activeStateFadeDuration
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(fade, forKey: "buoyActiveStateFade")
            }
            repaint(button)
        }
    }
}
