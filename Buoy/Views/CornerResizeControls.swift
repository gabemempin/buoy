import AppKit

/// Owns four small transparent child panels that sit around Buoy's real window frame.
/// Keeping the controls in child windows lets the arcs render and receive drags outside
/// the parent NSPanel without enlarging the visible glass surface.
final class CornerResizeOverlayController {
    private weak var parentWindow: NSWindow?
    private var overlays: [ResizeCorner: CornerResizeOverlay] = [:]
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var isEnabled = false
    private var hoveredCorner: ResizeCorner?
    private var isDragging = false
    private var transitionGeneration = 0

    func attach(to parentWindow: NSWindow) {
        detach()
        self.parentWindow = parentWindow
        parentWindow.acceptsMouseMovedEvents = true

        for corner in ResizeCorner.allCases {
            let overlay = makeOverlay(for: corner, parentWindow: parentWindow)
            overlays[corner] = overlay
            parentWindow.addChildWindow(overlay.panel, ordered: .above)
        }

        updateFrames()
        syncWindowProperties()
        installMouseMonitors()
    }

    func detach() {
        removeMouseMonitors()
        if let parentWindow {
            for overlay in overlays.values {
                parentWindow.removeChildWindow(overlay.panel)
                overlay.panel.close()
            }
        }
        overlays.removeAll()
        parentWindow = nil
        hoveredCorner = nil
        isDragging = false
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        transitionGeneration += 1

        if enabled {
            handleMouseMoved(to: NSEvent.mouseLocation)
        } else {
            hoveredCorner = nil
            isDragging = false
            reveal(nil, animated: true)
        }
    }

    func updateFrames() {
        guard let parentWindow else { return }
        for corner in ResizeCorner.allCases {
            overlays[corner]?.panel.setFrame(
                CornerResizeMetrics.overlayFrame(for: corner, around: parentWindow.frame),
                display: false
            )
        }
    }

    func syncWindowProperties() {
        guard let parentWindow else { return }
        for overlay in overlays.values {
            overlay.panel.level = parentWindow.level
            overlay.panel.collectionBehavior = parentWindow.collectionBehavior
            overlay.panel.appearance = parentWindow.appearance
            overlay.view.needsDisplay = true
        }
    }

    func parentDidShow() {
        updateFrames()
        guard isEnabled else { return }
        handleMouseMoved(to: NSEvent.mouseLocation)
    }

    func parentWillHide() {
        transitionGeneration += 1
        hoveredCorner = nil
        isDragging = false
        reveal(nil, animated: false)
    }

    func containsInteractiveControl(at screenPoint: NSPoint) -> Bool {
        overlays.values.contains {
            !$0.panel.ignoresMouseEvents && $0.panel.frame.contains(screenPoint)
        }
    }

    private func makeOverlay(
        for corner: ResizeCorner,
        parentWindow: NSWindow
    ) -> CornerResizeOverlay {
        let panel = CornerResizePanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: CornerResizeMetrics.overlaySize,
                    height: CornerResizeMetrics.overlaySize
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true

        let view = CornerResizeOverlayView(corner: corner, parentWindow: parentWindow)
        view.onDraggingChange = { [weak self] dragging in
            self?.handleDraggingChange(dragging)
        }
        panel.contentView = view
        return CornerResizeOverlay(panel: panel, view: view)
    }

    private func installMouseMonitors() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) {
            [weak self] event in
            self?.handleMouseMoved(to: NSEvent.mouseLocation)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) {
            [weak self] _ in
            let point = NSEvent.mouseLocation
            DispatchQueue.main.async {
                self?.handleMouseMoved(to: point)
            }
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

    private func handleMouseMoved(to screenPoint: NSPoint) {
        guard isEnabled,
              !isDragging,
              let parentWindow,
              parentWindow.isVisible
        else { return }

        var nextCorner = ResizeCorner.allCases
            .map { corner in
                (corner, corner.screenPoint(in: parentWindow.frame.insetBy(
                    dx: PanelLayoutMetrics.glassEdgeInset,
                    dy: PanelLayoutMetrics.glassEdgeInset
                )).distance(to: screenPoint))
            }
            .filter { $0.1 <= $0.0.proximityRadius }
            .min { $0.1 < $1.1 }?
            .0

        // The traffic lights sit inside the top-leading proximity radius (their
        // nearest corner is ~20pt from the window corner, the radius is 22), and a
        // revealed overlay is a mouse-opaque child panel overlapping 24pt into the
        // window — enough to swallow the close button's hover and clicks. Punch the
        // lights out of that corner's hit region, and dismiss without the usual
        // delay so the arc can't linger on top of them.
        var dismissImmediately = false
        if nextCorner == .topLeading,
           let trafficLights = TrafficLightGroupView.screenFrame(padding: 4),
           trafficLights.contains(screenPoint) {
            nextCorner = nil
            dismissImmediately = true
        }

        // Visibility follows proximity; click capture follows the arc itself.
        // Update this even while staying near the same corner, and release it
        // immediately on leaving the arc rather than waiting for its fade-out.
        updateMouseCapture(at: screenPoint)

        guard nextCorner != hoveredCorner else { return }
        hoveredCorner = nextCorner
        transitionGeneration += 1
        let generation = transitionGeneration

        if dismissImmediately {
            reveal(nil, animated: true)
        } else if let nextCorner {
            DispatchQueue.main.asyncAfter(deadline: .now() + CornerResizeMetrics.revealDelay) {
                [weak self] in
                guard let self,
                      self.isEnabled,
                      !self.isDragging,
                      self.hoveredCorner == nextCorner,
                      self.transitionGeneration == generation
                else { return }
                self.reveal(nextCorner, animated: true)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + CornerResizeMetrics.dismissDelay) {
                [weak self] in
                guard let self,
                      !self.isDragging,
                      self.hoveredCorner == nil,
                      self.transitionGeneration == generation
                else { return }
                self.reveal(nil, animated: true)
            }
        }
    }

    /// Told when a corner drag starts and stops. The delegate defers anything
    /// that would move the window itself until the user lets go.
    var onDraggingChange: ((Bool) -> Void)?

    private func handleDraggingChange(_ dragging: Bool) {
        isDragging = dragging
        onDraggingChange?(dragging)
        transitionGeneration += 1
        if dragging {
            return
        }

        handleMouseMoved(to: NSEvent.mouseLocation)
    }

    private func updateMouseCapture(at screenPoint: NSPoint) {
        for (corner, overlay) in overlays {
            overlay.panel.ignoresMouseEvents = !(corner == hoveredCorner
                && overlay.view.alphaValue > 0
                && overlay.view.containsResizeHandle(at: screenPoint))
        }
    }

    private func reveal(_ corner: ResizeCorner?, animated: Bool) {
        for (candidate, overlay) in overlays {
            let shouldReveal = candidate == corner && isEnabled
            overlay.panel.ignoresMouseEvents = !shouldReveal
                || !overlay.view.containsResizeHandle(at: NSEvent.mouseLocation)
            overlay.view.setRevealed(shouldReveal, animated: animated)
        }
    }
}

private struct CornerResizeOverlay {
    let panel: CornerResizePanel
    let view: CornerResizeOverlayView
}

private enum CornerResizeMetrics {
    static let overlaySize: CGFloat = 52
    static let outsideExtent: CGFloat = 28
    static let insideOverlap: CGFloat = overlaySize - outsideExtent
    static let arcRadius: CGFloat = PanelLayoutMetrics.windowCornerRadius + 9
    /// Trims this many degrees from both ends of the 90-degree corner arc.
    /// Increase to shorten the arc; decrease to lengthen it. Keep below 45.
    static let arcTrimDegrees: CGFloat = 20
    static let revealDelay: TimeInterval = 0.16
    static let dismissDelay: TimeInterval = 0.34
    static let strokeWidth: CGFloat = 3.25
    static let draggingStrokeWidth: CGFloat = 4.25
    static let draggingRadiusExpansion: CGFloat = 2
    static let topProximityRadius: CGFloat = 22
    static let bottomProximityRadius: CGFloat = 36

    static func overlayFrame(for corner: ResizeCorner, around parentFrame: NSRect) -> NSRect {
        // Anchor to the *glass* corner, not the window corner — the window frame
        // extends glassEdgeInset past the visible surface on every side.
        let glass = parentFrame.insetBy(
            dx: PanelLayoutMetrics.glassEdgeInset,
            dy: PanelLayoutMetrics.glassEdgeInset
        )
        let x = corner.isLeading
            ? glass.minX - outsideExtent
            : glass.maxX - insideOverlap
        let y = corner.isTop
            ? glass.maxY - insideOverlap
            : glass.minY - outsideExtent
        return NSRect(x: x, y: y, width: overlaySize, height: overlaySize)
    }
}

private enum ResizeCorner: CaseIterable, Hashable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var isLeading: Bool {
        self == .topLeading || self == .bottomLeading
    }

    var isTop: Bool {
        self == .topLeading || self == .topTrailing
    }

    var proximityRadius: CGFloat {
        isTop
            ? CornerResizeMetrics.topProximityRadius
            : CornerResizeMetrics.bottomProximityRadius
    }

    var cursorPosition: NSCursor.FrameResizePosition {
        switch self {
        case .topLeading: .topLeft
        case .topTrailing: .topRight
        case .bottomLeading: .bottomLeft
        case .bottomTrailing: .bottomRight
        }
    }

    func screenPoint(in frame: NSRect) -> NSPoint {
        NSPoint(
            x: isLeading ? frame.minX : frame.maxX,
            y: isTop ? frame.maxY : frame.minY
        )
    }
}

private final class CornerResizePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The overlay reaches 28pt past the glass. With the panel under the menu
    /// bar, AppKit would push it down and the arc would miss the corner.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class CornerResizeOverlayView: NSView {
    let corner: ResizeCorner
    weak var parentWindow: NSWindow?
    var onDraggingChange: ((Bool) -> Void)?

    private var isDragging = false
    private var dragStartMouseLocation: NSPoint = .zero
    private var dragStartWindowFrame: NSRect = .zero
    @objc dynamic private var dragEmphasis: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    init(corner: ResizeCorner, parentWindow: NSWindow) {
        self.corner = corner
        self.parentWindow = parentWindow
        super.init(frame: NSRect(
            origin: .zero,
            size: NSSize(
                width: CornerResizeMetrics.overlaySize,
                height: CornerResizeMetrics.overlaySize
            )
        ))
        wantsLayer = true
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        if key == "dragEmphasis" {
            return CABasicAnimation()
        }
        return super.defaultAnimation(forKey: key)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(
            bounds,
            cursor: NSCursor.frameResize(position: corner.cursorPosition, directions: .all)
        )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = resizeArcPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let arcColor = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white
            : BuoyTheme.current.accentNSColor
        let strokeWidth = CornerResizeMetrics.strokeWidth
            + ((CornerResizeMetrics.draggingStrokeWidth - CornerResizeMetrics.strokeWidth)
                * dragEmphasis)

        arcColor.withAlphaComponent(0.2).setStroke()
        path.lineWidth = strokeWidth + 2.5
        path.stroke()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()

        arcColor.setStroke()
        path.lineWidth = strokeWidth
        path.stroke()
    }

    func setRevealed(_ revealed: Bool, animated: Bool) {
        if !revealed {
            isDragging = false
            setDraggingAppearance(false)
        }

        let targetAlpha: CGFloat = revealed ? 1 : 0
        guard abs(alphaValue - targetAlpha) > 0.001 else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = revealed ? 0.18 : 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = targetAlpha
            }
        } else {
            alphaValue = targetAlpha
        }
    }

    /// A narrow band around the drawn arc, never the transparent square over
    /// the footer. Reflect every corner into the same outward-facing quadrant.
    func containsResizeHandle(at screenPoint: NSPoint) -> Bool {
        guard let parentWindow, let window,
              window.frame.contains(screenPoint) else { return false }
        let glass = parentWindow.frame.insetBy(
            dx: PanelLayoutMetrics.glassEdgeInset,
            dy: PanelLayoutMetrics.glassEdgeInset
        )
        let cornerPoint = corner.screenPoint(in: glass)
        let radius = PanelLayoutMetrics.windowCornerRadius
        let outwardX = (screenPoint.x - cornerPoint.x) * (corner.isLeading ? -1 : 1) + radius
        let outwardY = (screenPoint.y - cornerPoint.y) * (corner.isTop ? 1 : -1) + radius
        let angle = atan2(outwardY, outwardX) * 180 / .pi
        let trim = CornerResizeMetrics.arcTrimDegrees
        return angle >= trim - 8 && angle <= 90 - trim + 8
            && abs(hypot(outwardX, outwardY) - CornerResizeMetrics.arcRadius) <= 5
    }

    override func mouseDown(with event: NSEvent) {
        guard let parentWindow else { return }
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowFrame = parentWindow.frame
        isDragging = true
        setDraggingAppearance(true)
        onDraggingChange?(true)
    }

    /// Each axis follows the pointer independently; the opposite corner stays fixed.
    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let parentWindow else { return }

        let start = dragStartWindowFrame
        let mouseLocation = NSEvent.mouseLocation
        let deltaX = mouseLocation.x - dragStartMouseLocation.x
        let deltaY = mouseLocation.y - dragStartMouseLocation.y
        var size = NSSize(
            width: corner.isLeading ? start.width - deltaX : start.width + deltaX,
            height: corner.isTop ? start.height + deltaY : start.height - deltaY
        )

        // Clamp the glass, not the window, so a corner drag can reach the edge.
        if let visibleFrame = (parentWindow.screen ?? NSScreen.main)?.visibleFrame.insetBy(
            dx: -PanelLayoutMetrics.glassEdgeInset,
            dy: -PanelLayoutMetrics.glassEdgeInset
        ) {
            size.width = min(size.width, corner.isLeading
                ? start.maxX - visibleFrame.minX : visibleFrame.maxX - start.minX)
            size.height = min(size.height, corner.isTop
                ? visibleFrame.maxY - start.minY : start.maxY - visibleFrame.minY)
        }
        // Keep each floor independent so a wide window can still become short.
        size.width = max(size.width, parentWindow.minSize.width, PanelLayoutMetrics.minimumWindowWidth)
        size.height = max(size.height, parentWindow.minSize.height, PanelLayoutMetrics.minimumWindowHeight)
        // setFrame does not invoke the delegate, which also enforces overlay floors.
        size = parentWindow.delegate?.windowWillResize?(parentWindow, to: size) ?? size
        size.width = size.width.rounded()
        size.height = size.height.rounded()

        var frame = start
        frame.size = size
        frame.origin.x = corner.isLeading ? start.maxX - size.width : start.minX
        frame.origin.y = corner.isTop ? start.minY : start.maxY - size.height
        parentWindow.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        setDraggingAppearance(false)
        onDraggingChange?(false)
    }

    private func setDraggingAppearance(_ dragging: Bool) {
        let targetEmphasis: CGFloat = dragging ? 1 : 0
        guard abs(dragEmphasis - targetEmphasis) > 0.001 else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = dragging ? 0.14 : 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().dragEmphasis = targetEmphasis
        }
    }

    private func resizeArcPath() -> NSBezierPath {
        let radius = CornerResizeMetrics.arcRadius
            + (CornerResizeMetrics.draggingRadiusExpansion * dragEmphasis)
        let trim = min(max(CornerResizeMetrics.arcTrimDegrees, 0), 44)
        // Overlay frames are anchored to the glass rect (see overlayFrame), so in
        // local coordinates the glass corner sits exactly where the window corner
        // used to — the original constants apply unchanged.
        let parentCorner = NSPoint(
            x: corner.isLeading
                ? CornerResizeMetrics.outsideExtent
                : CornerResizeMetrics.insideOverlap,
            y: corner.isTop
                ? CornerResizeMetrics.insideOverlap
                : CornerResizeMetrics.outsideExtent
        )
        let center = NSPoint(
            x: parentCorner.x + (corner.isLeading
                ? PanelLayoutMetrics.windowCornerRadius
                : -PanelLayoutMetrics.windowCornerRadius),
            y: parentCorner.y + (corner.isTop
                ? -PanelLayoutMetrics.windowCornerRadius
                : PanelLayoutMetrics.windowCornerRadius)
        )

        let path = NSBezierPath()
        switch corner {
        case .topLeading:
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 180 - trim,
                endAngle: 90 + trim,
                clockwise: true
            )
        case .topTrailing:
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90 - trim,
                endAngle: trim,
                clockwise: true
            )
        case .bottomLeading:
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 180 + trim,
                endAngle: 270 - trim,
                clockwise: false
            )
        case .bottomTrailing:
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 270 + trim,
                endAngle: 360 - trim,
                clockwise: false
            )
        }
        return path
    }
}

private extension NSPoint {
    func distance(to other: NSPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
