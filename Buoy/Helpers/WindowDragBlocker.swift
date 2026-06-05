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

/// Forces the arrow cursor over overlay panels, preventing NSTextView's
/// I-beam from bleeding through. Apply as .overlay(.allowsHitTesting(false))
/// so it sits above all content in z-order and intercepts cursorUpdate events
/// before they propagate up the responder chain to BuoyTextView.
struct ArrowCursorOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> ArrowCursorNSView { ArrowCursorNSView() }
    func updateNSView(_ nsView: ArrowCursorNSView, context: Context) {}
}

final class ArrowCursorNSView: NSView {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
        // Do NOT call super — stops propagation to BuoyTextView's tracking area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

/// Re-enables window dragging for a specific region (e.g. the header bar).
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragEnablingNSView { DragEnablingNSView() }
    func updateNSView(_ nsView: DragEnablingNSView, context: Context) {}
}

final class DragEnablingNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    private var dragStartMouse: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let loc = NSEvent.mouseLocation
        var origin = NSPoint(
            x: dragStartWindowOrigin.x + loc.x - dragStartMouse.x,
            y: dragStartWindowOrigin.y + loc.y - dragStartMouse.y
        )
        // Keep the panel inside the screen's visible frame so it can't be dragged
        // up under the menu bar or off any edge into an unreachable position.
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            let size = window.frame.size
            let maxX = max(visible.minX, visible.maxX - size.width)
            let maxY = max(visible.minY, visible.maxY - size.height)
            origin.x = min(max(origin.x, visible.minX), maxX)
            origin.y = min(max(origin.y, visible.minY), maxY)
        }
        window.setFrameOrigin(origin)
    }
}
