import AppKit

/// Buoy's main menu bar.
///
/// Split out of `AppDelegate` because a standards-compliant macOS menu is long
/// and almost entirely declarative. Every item here either targets the responder
/// chain (`target == nil`) so AppKit's automatic menu validation enables and
/// disables it against whatever is focused, or targets the delegate for the
/// handful of app-level commands.
///
/// The Edit menu deliberately mirrors AppKit's standard `MainMenu.xib` — Paste
/// and Match Style, Spelling and Grammar, Substitutions, Transformations and
/// Speech are all free from `NSTextView`, and users reasonably expect a text
/// editor to have them.
///
/// **This menu is only on screen while "Show in Dock" is enabled.** With it off
/// Buoy runs as an `.accessory` app, which by definition has no menu bar, so the
/// status item's own menu (`AppDelegate.showContextMenu`) is the discoverable
/// surface for those users and carries the same app-level commands.
extension AppDelegate {

    // MARK: - Construction

    func buildMainMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenu: buildAppMenu())
        mainMenu.addItem(submenu: buildEditMenu())
        mainMenu.addItem(submenu: buildFormatMenu())
        mainMenu.addItem(submenu: buildWindowMenu())
        NSApp.mainMenu = mainMenu
        refreshMinimizeMenuItem()
    }

    // MARK: - Buoy

    private func buildAppMenu() -> NSMenu {
        let menu = NSMenu(title: "Buoy")

        menu.addItem(
            title: "About Buoy",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        )
        menu.addItem(.separator())

        // HIG: the app menu is where users look for preferences, and ⌘, is the
        // system-wide key equivalent for it. Before this, Settings was reachable
        // only by right-clicking the menu bar icon.
        menu.addItem(
            title: "Settings…",
            action: #selector(openSettings),
            command: .openSettings,
            target: self
        )
        menu.addItem(.separator())

        let servicesItem = menu.addItem(title: "Services", action: nil)
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(.separator())

        menu.addItem(title: "Hide Buoy", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifiers: [.command, .option]
        )
        menu.addItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)))
        menu.addItem(.separator())

        menu.addItem(title: "Quit Buoy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    // MARK: - Edit

    private func buildEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        // Keeps Undo/Redo titles naming the actual action ("Undo Typing") the way
        // every other macOS text editor does.
        menu.delegate = editMenuDelegate

        menu.addItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z",
            modifiers: [.command, .shift]
        )
        menu.addItem(.separator())

        menu.addItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            title: "Paste and Match Style",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v",
            modifiers: [.command, .option, .shift]
        )
        menu.addItem(title: "Delete", action: #selector(NSText.delete(_:)))
        menu.addItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())

        // Buoy's own find bar, not AppKit's — see BuoyTextView.commonInit for
        // why the system one cannot be used in this panel.
        menu.addItem(
            title: "Find in Note…",
            action: #selector(BuoyTextView.findInNoteAction(_:)),
            command: .findInNote
        )
        menu.addItem(.separator())
        menu.addItem(submenu: buildSpellingMenu())
        menu.addItem(submenu: buildSubstitutionsMenu())
        menu.addItem(submenu: buildTransformationsMenu())
        menu.addItem(submenu: buildSpeechMenu())
        return menu
    }

    private func buildSpellingMenu() -> NSMenu {
        let menu = NSMenu(title: "Spelling and Grammar")
        menu.addItem(
            title: "Show Spelling and Grammar",
            action: #selector(NSText.showGuessPanel(_:)),
            keyEquivalent: ":"
        )
        menu.addItem(
            title: "Check Document Now",
            action: #selector(NSText.checkSpelling(_:)),
            keyEquivalent: ";"
        )
        menu.addItem(.separator())
        menu.addItem(
            title: "Check Spelling While Typing",
            action: #selector(NSTextView.toggleContinuousSpellChecking(_:))
        )
        menu.addItem(
            title: "Check Grammar With Spelling",
            action: #selector(NSTextView.toggleGrammarChecking(_:))
        )
        menu.addItem(
            title: "Correct Spelling Automatically",
            action: #selector(NSTextView.toggleAutomaticSpellingCorrection(_:))
        )
        return menu
    }

    private func buildSubstitutionsMenu() -> NSMenu {
        let menu = NSMenu(title: "Substitutions")
        menu.addItem(
            title: "Show Substitutions",
            action: #selector(NSTextView.orderFrontSubstitutionsPanel(_:))
        )
        menu.addItem(.separator())
        menu.addItem(title: "Smart Copy/Paste", action: #selector(NSTextView.toggleSmartInsertDelete(_:)))
        menu.addItem(title: "Smart Quotes", action: #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)))
        menu.addItem(title: "Smart Dashes", action: #selector(NSTextView.toggleAutomaticDashSubstitution(_:)))
        menu.addItem(title: "Smart Links", action: #selector(NSTextView.toggleAutomaticLinkDetection(_:)))
        menu.addItem(title: "Text Replacement", action: #selector(NSTextView.toggleAutomaticTextReplacement(_:)))
        return menu
    }

    private func buildTransformationsMenu() -> NSMenu {
        let menu = NSMenu(title: "Transformations")
        menu.addItem(title: "Make Upper Case", action: #selector(NSResponder.uppercaseWord(_:)))
        menu.addItem(title: "Make Lower Case", action: #selector(NSResponder.lowercaseWord(_:)))
        menu.addItem(title: "Capitalize", action: #selector(NSResponder.capitalizeWord(_:)))
        return menu
    }

    private func buildSpeechMenu() -> NSMenu {
        let menu = NSMenu(title: "Speech")
        menu.addItem(title: "Start Speaking", action: #selector(NSTextView.startSpeaking(_:)))
        menu.addItem(title: "Stop Speaking", action: #selector(NSTextView.stopSpeaking(_:)))
        return menu
    }

    // MARK: - Format

    /// Buoy is a rich text editor, so its formatting commands belong in a menu.
    /// `BuoyTextView.performKeyEquivalent` still handles these keystrokes first
    /// while the editor is focused; the menu makes them discoverable and gives
    /// them the standard validation behaviour when it is not.
    private func buildFormatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        menu.addItem(title: "Bold", action: #selector(BuoyTextView.boldAction(_:)), keyEquivalent: "b")
        menu.addItem(title: "Italic", action: #selector(BuoyTextView.italicAction(_:)), keyEquivalent: "i")
        menu.addItem(title: "Underline", action: #selector(BuoyTextView.underlineAction(_:)), keyEquivalent: "u")
        menu.addItem(
            title: "Strikethrough",
            action: #selector(BuoyTextView.strikethroughAction(_:)),
            keyEquivalent: "x",
            modifiers: [.command, .shift]
        )
        menu.addItem(.separator())
        menu.addItem(title: "Bulleted List", action: #selector(BuoyTextView.bulletListAction(_:)))
        menu.addItem(title: "To-Do List", action: #selector(BuoyTextView.todoListAction(_:)))
        menu.addItem(.separator())
        menu.addItem(
            title: "Add Link…",
            action: #selector(BuoyTextView.linkAction(_:)),
            command: .insertLink
        )
        return menu
    }

    // MARK: - Window

    private func buildWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        minimizeRestoreMenuItem = menu.addItem(
            title: "Minimize",
            action: #selector(toggleMinimizedMode(_:)),
            command: .harborMode,
            target: self
        )
        menu.addItem(title: "Zoom", action: #selector(NSWindow.zoom(_:)))
        menu.addItem(.separator())
        menu.addItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)))
        return menu
    }
}

// MARK: - Undo/Redo titles

/// Keeps the Edit menu's Undo and Redo items naming the operation they would
/// reverse. AppKit only does this automatically for document-based apps, so a
/// menu delegate reads the titles off the key window's undo manager each time
/// the menu is about to open.
final class EditMenuDelegate: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let manager = NSApp.keyWindow?.undoManager
        for item in menu.items {
            switch item.action {
            case Selector(("undo:")):
                item.title = manager?.undoMenuItemTitle ?? "Undo"
            case Selector(("redo:")):
                item.title = manager?.redoMenuItemTitle ?? "Redo"
            default:
                continue
            }
        }
    }
}

// MARK: - NSMenu conveniences

private extension NSMenu {
    /// Adds an item wired to the responder chain unless an explicit target is given.
    @discardableResult
    func addItem(
        title: String,
        action: Selector?,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags? = nil,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = addItem(withTitle: title, action: action, keyEquivalent: keyEquivalent)
        if let modifiers { item.keyEquivalentModifierMask = modifiers }
        item.target = target
        return item
    }

    /// Adds an item whose key equivalent follows a rebindable Buoy command.
    ///
    /// The menu bar stores key equivalents as literal characters, so it cannot
    /// consult `ShortcutRegistry` at match time — the menu has to be rebuilt
    /// when a binding changes, which `AppDelegate.handleSettingsUpdate` does.
    /// A combo whose key has no menu character (an arrow, say) leaves the item
    /// with no key equivalent rather than a wrong one.
    @discardableResult
    func addItem(
        title: String,
        action: Selector?,
        command: BuoyCommand,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let equivalent = ShortcutRegistry.combo(for: command).menuKeyEquivalent
        return addItem(
            title: title,
            action: action,
            keyEquivalent: equivalent?.key ?? "",
            modifiers: equivalent?.modifiers,
            target: target
        )
    }

    /// Adds a top-level item whose only job is to carry `submenu`.
    func addItem(submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
