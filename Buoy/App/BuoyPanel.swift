import AppKit

/// NSPanel subclass that can become key, enabling keyboard input in
/// the contained SwiftUI text views while still using .nonactivatingPanel.
final class BuoyPanel: NSPanel {
    var allowsKeyFocus = true

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }

    /// Provide a persistent undo manager so NSTextView (allowsUndo = true) can
    /// register undo actions for normal typing. Without this the responder chain
    /// finds no undo manager and ⌘Z silently does nothing.
    private let _undoManager = UndoManager()
    override var undoManager: UndoManager? { _undoManager }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            allowsKeyFocus = true
            if !isKeyWindow {
                makeKey()
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .help, .capsLock])

        // Non-activating panels do not reliably participate in the normal Window
        // menu key-equivalent routing, so handle ⌘M at the panel level.
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "m" {
            return NSApp.sendAction(
                #selector(AppDelegate.toggleMinimizedMode(_:)),
                to: NSApp.delegate,
                from: self
            )
        }

        return super.performKeyEquivalent(with: event)
    }
}
