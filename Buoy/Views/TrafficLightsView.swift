import SwiftUI
import AppKit

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

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose, onMinimize: onMinimize, onExpand: onExpand)
    }

    func makeNSView(context: Context) -> TrafficLightGroupView {
        TrafficLightGroupView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: TrafficLightGroupView, context: Context) {
        context.coordinator.onClose = onClose
        context.coordinator.onMinimize = onMinimize
        context.coordinator.onExpand = onExpand
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

    private var buttons: [NSButton] = []
    private var isMouseInGroup = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

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

    deinit { removeMouseMonitors() }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { buttonsRect.size }

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
        if let window {
            Self.liveGroup = self
            // Don't rely on the corner-resize controller having set this.
            window.acceptsMouseMovedEvents = true
            installMouseMonitors()
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
        for button in buttons {
            if button.responds(to: Self.repaintSelector) {
                _ = button.perform(Self.repaintSelector)
            } else {
                // Wrong glyphs beat a crash if AppKit ever renames that hook.
                button.needsDisplay = true
            }
        }
    }
}
