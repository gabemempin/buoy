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

    func makeNSView(context: Context) -> DragEnablingNSView {
        let view = DragEnablingNSView()
        view.onDoubleClick = onDoubleClick
        return view
    }
    func updateNSView(_ nsView: DragEnablingNSView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}

final class DragEnablingNSView: NSView {
    var onDoubleClick: (() -> Void)?
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
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDoubleClick, let window = window else { return }
        let loc = NSEvent.mouseLocation
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
