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

/// Re-enables window dragging for a specific region (e.g. the header bar).
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragEnablingNSView { DragEnablingNSView() }
    func updateNSView(_ nsView: DragEnablingNSView, context: Context) {}
}

final class DragEnablingNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    private var dragOrigin: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let loc = NSEvent.mouseLocation
        let newOrigin = NSPoint(
            x: window.frame.origin.x + loc.x - dragOrigin.x,
            y: window.frame.origin.y + loc.y - dragOrigin.y
        )
        window.setFrameOrigin(newOrigin)
        dragOrigin = loc
    }
}
