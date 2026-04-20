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

        //Handler for Cmd+W at the panel level
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            return NSApp.sendAction(
                #selector(AppDelegate.hidePanel(_:)),
                to: NSApp.delegate,
                from: self
            )
        }

        // Try the normal view-hierarchy dispatch first. If BuoyTextView is the
        // first responder it will claim the event there.
        if super.performKeyEquivalent(with: event) {
            return true
        }

        // ⌘← / ⌘→ — switch notes regardless of which view has focus.
        // BuoyTextView handles this when it's first responder (above), but when
        // focus is elsewhere (e.g. title field, settings panel) the event falls
        // through to here.
        if modifiers == .command {
            switch event.keyCode {
            case 123: // ←
                NotificationCenter.default.post(name: .buoyPreviousNote, object: nil)
                return true
            case 124: // →
                NotificationCenter.default.post(name: .buoyNextNote, object: nil)
                return true
            default:
                break
            }
        }

        // Non-activating panels don't reliably trigger main-menu key equivalents,
        // so standard editing shortcuts (⌘C/⌘V/⌘X/⌘A/⌘Z) never reach the first
        // responder (e.g. the field editor for a SwiftUI TextField). Route them
        // explicitly here.
        guard let fr = firstResponder else { return false }
        let ch = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if modifiers == [.command, .shift], event.keyCode == 6 /* Z */ {
            fr.tryToPerform(Selector(("redo:")), with: nil)
            return true
        }

        guard modifiers == .command else { return false }
        let action: Selector? = switch ch {
        case "c": #selector(NSText.copy(_:))
        case "v": #selector(NSText.paste(_:))
        case "x": #selector(NSText.cut(_:))
        case "a": #selector(NSText.selectAll(_:))
        case "z": Selector(("undo:"))
        default: nil
        }
        guard let action else { return false }
        if fr.tryToPerform(action, with: nil) {
            return true
        }
        return false
    }
}
