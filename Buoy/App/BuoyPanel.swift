import AppKit

/// NSPanel subclass that can become key, enabling keyboard input in
/// the contained SwiftUI text views while still using .nonactivatingPanel.
final class BuoyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Provide a persistent undo manager so NSTextView (allowsUndo = true) can
    /// register undo actions for normal typing. Without this the responder chain
    /// finds no undo manager and ⌘Z silently does nothing.
    private let _undoManager = UndoManager()
    override var undoManager: UndoManager? { _undoManager }
}
