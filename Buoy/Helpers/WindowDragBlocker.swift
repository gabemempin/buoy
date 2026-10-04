import AppKit
import SwiftUI

/// Prevents the parent NSPanel from being dragged when interacting with
/// controls inside this overlay panel. Returns mouseDownCanMoveWindow = false.
struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> DragBlockingNSView { DragBlockingNSView() }
    func updateNSView(_ nsView: DragBlockingNSView, context: Context) {}
}

final class DragBlockingNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Shows the pointing-hand cursor while hovering a control. Overlay panels
/// suppress BuoyTextView's I-beam at the source (BuoyTextView.suppressesIBeamCursor),
/// so this only needs to push/pop the hand cursor for its own hover state.
struct PointingHandCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else if isHovering {
                    NSCursor.pop()
                }
                isHovering = hovering
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}

/// Re-enables window dragging for a specific region (e.g. the header bar).
struct WindowDragHandle: NSViewRepresentable {
    var onDoubleClick: (() -> Void)? = nil
    /// Fired when the drag turns into a shake (see `ShakeDetector`).
    var onShake: (() -> Void)? = nil

    func makeNSView(context: Context) -> DragEnablingNSView {
        let view = DragEnablingNSView()
        view.onDoubleClick = onDoubleClick
        view.onShake = onShake
        return view
    }
    func updateNSView(_ nsView: DragEnablingNSView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
        nsView.onShake = onShake
    }
}

/// Recognises a back-and-forth shake from a stream of one-axis positions:
/// `reversals` direction changes, each after travelling at least `minSwing`
/// points, all inside `window` seconds.
struct ShakeDetector {
    private let minSwing: CGFloat = 26
    private let reversals = 4
    private let window: TimeInterval = 0.8

    private var direction: CGFloat = 0
    private var extreme: CGFloat = 0
    private var reversalTimes: [TimeInterval] = []

    mutating func reset() {
        direction = 0
        reversalTimes.removeAll()
    }

    mutating func add(_ value: CGFloat, at time: TimeInterval) -> Bool {
        if direction == 0 {
            extreme = value
            direction = 1
            return false
        }
        if (value - extreme) * direction > 0 {
            extreme = value // still travelling the same way
            return false
        }
        guard abs(value - extreme) >= minSwing else { return false }

        direction = -direction
        extreme = value
        reversalTimes.append(time)
        reversalTimes.removeAll { time - $0 > window }
        guard reversalTimes.count >= reversals else { return false }
        reset()
        return true
    }
}

final class DragEnablingNSView: NSView {
    var onDoubleClick: (() -> Void)?
    var onShake: (() -> Void)?
    private var shakeX = ShakeDetector()
    private var shakeY = ShakeDetector()
    /// One toggle per gesture: carrying on shaking must not flip it straight back.
    private var didShake = false
    private var isDoubleClick = false
    override var mouseDownCanMoveWindow: Bool { false }
    private var dragStartMouse: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        isDoubleClick = event.clickCount == 2 && onDoubleClick != nil
        if isDoubleClick {
            onDoubleClick?()
            return
        }
        dragStartMouse = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin ?? .zero
        didShake = false
        shakeX.reset()
        shakeY.reset()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDoubleClick, let window = window else { return }
        let loc = NSEvent.mouseLocation
        if onShake != nil, !didShake {
            // Screen coordinates, so the window following the pointer doesn't
            // hide the motion.
            let now = event.timestamp
            let shookX = shakeX.add(loc.x, at: now)
            let shookY = shakeY.add(loc.y, at: now)
            if shookX || shookY {
                didShake = true
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                onShake?()
            }
        }
        var origin = NSPoint(
            x: dragStartWindowOrigin.x + loc.x - dragStartMouse.x,
            y: dragStartWindowOrigin.y + loc.y - dragStartMouse.y
        )
        // Keep the panel inside the screen's visible frame so it can't be dragged
        // up under the menu bar or off any edge into an unreachable position.
        // Clamp the *glass*, not the window: the frame extends glassEdgeInset
        // past the visible surface, so let that transparent margin overhang the
        // screen edge — otherwise the panel stops visibly short of the edge.
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame.insetBy(
            dx: -PanelLayoutMetrics.glassEdgeInset,
            dy: -PanelLayoutMetrics.glassEdgeInset
        ) {
            let size = window.frame.size
            let maxX = max(visible.minX, visible.maxX - size.width)
            let maxY = max(visible.minY, visible.maxY - size.height)
            origin.x = min(max(origin.x, visible.minX), maxX)
            origin.y = min(max(origin.y, visible.minY), maxY)
        }
        window.setFrameOrigin(origin)
    }
}
