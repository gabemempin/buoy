import AppKit

/// The one place that decides what a keystroke means.
///
/// Before this, six places did: `BuoyTextView.keyDown`, its
/// `performKeyEquivalent`, `BuoyPanel.performKeyEquivalent`, the main menu's
/// key equivalents, the status item's menu, and a hand-written list in the
/// Shortcuts panel — which had already drifted out of step with the others.
/// Dispatch now happens at the panel and everything else reads its bindings
/// from here.
enum ShortcutRegistry {
    /// The user's overrides, keyed by `BuoyCommand.rawValue`. Only changed
    /// bindings are stored, so a default that moves in a later release moves
    /// for everyone who never touched it.
    static private(set) var overrides: [String: KeyCombo] = [:]

    static func update(from settings: AppSettings) {
        overrides = settings.shortcuts
    }

    static func combo(for command: BuoyCommand) -> KeyCombo {
        overrides[command.rawValue] ?? command.defaultCombo
    }

    static func isCustomised(_ command: BuoyCommand) -> Bool {
        overrides[command.rawValue] != nil
    }

    static func conflict(
        for combo: KeyCombo,
        excluding excluded: BuoyCommand?,
        isGlobal: Bool,
        settings: AppSettings
    ) -> String? {
        if excluded == .hidePanel && combo == BuoyCommand.hidePanel.defaultCombo { return nil }
        let reserved: [(KeyCombo, String)] = [
            (KeyCombo(keyCode: 49, modifiers: .command), "macOS"),
            (KeyCombo(keyCode: 48, modifiers: .command), "macOS"),
            (KeyCombo(keyCode: 18, modifiers: [.command, .shift]), "macOS"),
            (KeyCombo(keyCode: 19, modifiers: [.command, .shift]), "macOS"),
            (KeyCombo(keyCode: 20, modifiers: [.command, .shift]), "macOS"),
            (KeyCombo(keyCode: 21, modifiers: [.command, .shift]), "macOS"),
            (KeyCombo(keyCode: 23, modifiers: [.command, .shift]), "macOS"),
            (KeyCombo(keyCode: 12, modifiers: .command), "Quit Buoy"),
            (KeyCombo(keyCode: 13, modifiers: .command), "Close Settings"),
            (KeyCombo(keyCode: 4, modifiers: .command), "Hide Buoy application"),
            (KeyCombo(keyCode: 4, modifiers: [.command, .option]), "Hide Others"),
            (KeyCombo(keyCode: 0, modifiers: .command), "Select All"),
            (KeyCombo(keyCode: 8, modifiers: .command), "Copy"),
            (KeyCombo(keyCode: 9, modifiers: .command), "Paste"),
            (KeyCombo(keyCode: 9, modifiers: [.command, .option, .shift]), "Paste and Match Style"),
            (KeyCombo(keyCode: 7, modifiers: .command), "Cut"),
            (KeyCombo(keyCode: 6, modifiers: .command), "Undo"),
            (KeyCombo(keyCode: 6, modifiers: [.command, .shift]), "Redo"),
            (KeyCombo(keyCode: 11, modifiers: .command), "Bold"),
            (KeyCombo(keyCode: 34, modifiers: .command), "Italic"),
            (KeyCombo(keyCode: 32, modifiers: .command), "Underline"),
            (KeyCombo(keyCode: 7, modifiers: [.command, .shift]), "Strikethrough")
        ]
        if let owner = reserved.first(where: { $0.0 == combo })?.1 { return owner }
        if !isGlobal, KeyCombo(electronString: settings.globalShortcut) == combo {
            return "Show or hide Buoy"
        }
        for command in BuoyCommand.allCases where command != excluded {
            if settings.shortcuts[command.rawValue] ?? command.defaultCombo == combo {
                return command.title
            }
        }
        return nil
    }

    /// The command a key event should run, if any.
    static func command(for event: NSEvent) -> BuoyCommand? {
        BuoyCommand.allCases.first { combo(for: $0).matches(event) }
    }

    /// Runs `command`. Most of these cross from the panel into SwiftUI, so they
    /// go by notification; the two that resize or hide the window are the
    /// delegate's business and go by selector.
    @discardableResult
    static func perform(_ command: BuoyCommand, from sender: Any?) -> Bool {
        switch command {
        case .newNote:      return post(.buoyNewNote)
        case .deleteNote:   return post(.buoyDeleteNote)
        case .copyNote:     return post(.buoyCopyToClipboard)
        case .previousNote: return post(.buoyPreviousNote)
        case .nextNote:     return post(.buoyNextNote)
        case .allNotes:     return post(.buoyToggleAllNotes)
        case .insertLink:   return post(.buoyInsertLink)
        case .harborMode:
            return NSApp.sendAction(
                #selector(AppDelegate.toggleMinimizedMode(_:)),
                to: NSApp.delegate,
                from: sender
            )
        case .openSettings:
            return NSApp.sendAction(#selector(AppDelegate.openSettings), to: NSApp.delegate, from: sender)
        case .hidePanel:
            return NSApp.sendAction(#selector(AppDelegate.hidePanel(_:)), to: NSApp.delegate, from: sender)
        }
    }

    private static func post(_ name: Notification.Name) -> Bool {
        NotificationCenter.default.post(name: name, object: nil)
        return true
    }
}

extension Notification.Name {
    static let buoyToggleAllNotes = Notification.Name("BuoyToggleAllNotes")
    static let buoyInsertLink = Notification.Name("BuoyInsertLink")
}
