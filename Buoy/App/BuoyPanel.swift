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

    /// AppKit pushes a window's *frame* below the menu bar whenever it is
    /// shown or resized, but this frame carries a transparent glassEdgeInset
    /// margin, so that left the glass stopping 12pt short of the top. Buoy
    /// clamps the glass itself (`clampedToVisibleFrame`, the header drag).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

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
        let commandCharacter = event.charactersIgnoringModifiers?.lowercased()

        // Every rebindable command, in one place and before the responder
        // chain gets a look.
        //
        // Ahead of `super` on purpose: these have to fire the same way whether
        // the editor, the title field or nothing at all has focus, and the
        // panel is non-activating so `NSApp.mainMenu`'s key equivalents cannot
        // be relied on to do it. The recorder refuses a combo without ⌘, ⌃ or
        // ⌥, which is what guarantees every binding arrives here as a key
        // equivalent rather than as ordinary typing.
        if let command = ShortcutRegistry.command(for: event) {
            return ShortcutRegistry.perform(command, from: self)
        }

        // Try the normal view-hierarchy dispatch first. If BuoyTextView is the
        // first responder it will claim the event there.
        if super.performKeyEquivalent(with: event) {
            return true
        }

        // Non-activating panels don't reliably trigger main-menu key equivalents,
        // so standard editing shortcuts (⌘C/⌘V/⌘X/⌘A/⌘Z) never reach the first
        // responder (e.g. the field editor for a SwiftUI TextField). Route them
        // explicitly here.
        guard let fr = firstResponder else { return false }

        if modifiers == [.command, .shift], event.keyCode == 6 /* Z */ {
            fr.tryToPerform(Selector(("redo:")), with: nil)
            return true
        }

        if modifiers == [.command, .option, .shift], commandCharacter == "v" {
            return fr.tryToPerform(#selector(NSTextView.pasteAsPlainText(_:)), with: nil)
        }

        guard modifiers == .command else { return false }

        let action: Selector? = switch commandCharacter ?? "" {
        case "c": #selector(NSText.copy(_:))
        case "v": #selector(NSText.paste(_:))
        case "x": #selector(NSText.cut(_:))
        case "a": #selector(NSText.selectAll(_:))
        case "z": Selector(("undo:"))
        case "j": #selector(NSResponder.centerSelectionInVisibleArea(_:))
        default: nil
        }
        guard let action else { return false }
        if fr.tryToPerform(action, with: nil) {
            return true
        }
        return false
    }
}
