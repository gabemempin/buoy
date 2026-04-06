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
    private var dragStartMouse: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let loc = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: dragStartWindowOrigin.x + loc.x - dragStartMouse.x,
            y: dragStartWindowOrigin.y + loc.y - dragStartMouse.y
        ))
    }
}
