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

        let nextCorner = ResizeCorner.allCases
            .map { corner in
                (corner, corner.screenPoint(in: parentWindow.frame).distance(to: screenPoint))
            }
            .filter { $0.1 <= $0.0.proximityRadius }
            .min { $0.1 < $1.1 }?
            .0

        guard nextCorner != hoveredCorner else { return }
        hoveredCorner = nextCorner
        transitionGeneration += 1
        let generation = transitionGeneration

        if let nextCorner {
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

    private func handleDraggingChange(_ dragging: Bool) {
        isDragging = dragging
        transitionGeneration += 1
        if dragging {
            return
        }

        handleMouseMoved(to: NSEvent.mouseLocation)
    }

    private func reveal(_ corner: ResizeCorner?, animated: Bool) {
        for (candidate, overlay) in overlays {
            let shouldReveal = candidate == corner && isEnabled
            overlay.panel.ignoresMouseEvents = !shouldReveal
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
        let x = corner.isLeading
            ? parentFrame.minX - outsideExtent
            : parentFrame.maxX - insideOverlap
        let y = corner.isTop
            ? parentFrame.maxY - insideOverlap
            : parentFrame.minY - outsideExtent
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
            : NSColor.controlAccentColor
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

    override func mouseDown(with event: NSEvent) {
        guard let parentWindow else { return }
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowFrame = parentWindow.frame
        isDragging = true
        setDraggingAppearance(true)
        onDraggingChange?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let parentWindow else { return }

        let mouseLocation = NSEvent.mouseLocation
        let deltaX = mouseLocation.x - dragStartMouseLocation.x
        let deltaY = mouseLocation.y - dragStartMouseLocation.y
        let minimumSize = NSSize(
            width: max(parentWindow.minSize.width, PanelLayoutMetrics.minimumWindowWidth),
            height: max(parentWindow.minSize.height, PanelLayoutMetrics.minimumWindowHeight)
        )
        let visibleFrame = (parentWindow.screen ?? NSScreen.main)?.visibleFrame

        var frame = dragStartWindowFrame
        if corner.isTop {
            let maximumHeight = visibleFrame.map { $0.maxY - dragStartWindowFrame.minY }
                ?? CGFloat.greatestFiniteMagnitude
            frame.size.height = min(
                max(dragStartWindowFrame.height + deltaY, minimumSize.height),
                maximumHeight
            )
            frame.origin.y = dragStartWindowFrame.minY
        } else {
            let maximumHeight = visibleFrame.map { dragStartWindowFrame.maxY - $0.minY }
                ?? CGFloat.greatestFiniteMagnitude
            frame.size.height = min(
                max(dragStartWindowFrame.height - deltaY, minimumSize.height),
                maximumHeight
            )
            frame.origin.y = dragStartWindowFrame.maxY - frame.height
        }

        if corner.isLeading {
            let maximumWidth = visibleFrame.map { dragStartWindowFrame.maxX - $0.minX }
                ?? CGFloat.greatestFiniteMagnitude
            frame.size.width = min(
                max(dragStartWindowFrame.width - deltaX, minimumSize.width),
                maximumWidth
            )
            frame.origin.x = dragStartWindowFrame.maxX - frame.width
        } else {
            let maximumWidth = visibleFrame.map { $0.maxX - dragStartWindowFrame.minX }
                ?? CGFloat.greatestFiniteMagnitude
            frame.size.width = min(
                max(dragStartWindowFrame.width + deltaX, minimumSize.width),
                maximumWidth
            )
            frame.origin.x = dragStartWindowFrame.minX
        }

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
