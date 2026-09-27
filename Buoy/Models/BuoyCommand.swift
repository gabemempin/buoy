import AppKit

/// Every in-app action the user can put on a key of their choosing.
///
/// Formatting is deliberately absent. ⌘B, ⌘I, ⌘U and ⌘⇧X mean the same thing
/// in every Mac app that has them, and the standard editing keys (⌘Z, ⌘A,
/// ⌘C/⌘V/⌘X, Tab) belong to the text system rather than to Buoy. Those are
/// listed on the Shortcuts page as a reference and cannot be changed.
enum BuoyCommand: String, CaseIterable, Codable, Hashable {
    case newNote
    case deleteNote
    case copyNote
    case previousNote
    case nextNote
    case allNotes
    case insertLink
    case findInNote
    case harborMode
    case openSettings
    case hidePanel

    var title: String {
        switch self {
        case .newNote:      return "New Note"
        case .deleteNote:   return "Delete Note"
        case .copyNote:     return "Copy Note"
        case .previousNote: return "Previous Note"
        case .nextNote:     return "Next Note"
        case .allNotes:     return "All Notes"
        case .insertLink:   return "Insert Link"
        case .findInNote:   return "Find in Note"
        case .harborMode:   return "Harbor Mode"
        case .openSettings: return "Settings"
        case .hidePanel:    return "Hide Buoy"
        }
    }

    var defaultCombo: KeyCombo {
        switch self {
        case .newNote:      return KeyCombo(keyCode: 45, modifiers: .command)   // N
        case .deleteNote:   return KeyCombo(keyCode: 51, modifiers: .command)   // Delete
        case .copyNote:     return KeyCombo(keyCode: 36, modifiers: .command)   // Return
        case .previousNote: return KeyCombo(keyCode: 123, modifiers: .command)  // Left
        case .nextNote:     return KeyCombo(keyCode: 124, modifiers: .command)  // Right
        // All Notes had no key at all before this; ⌘L was free and reads as
        // "list".
        case .allNotes:     return KeyCombo(keyCode: 37, modifiers: .command)   // L
        case .insertLink:   return KeyCombo(keyCode: 40, modifiers: .command)   // K
        case .findInNote:   return KeyCombo(keyCode: 3, modifiers: .command)    // F
        case .harborMode:   return KeyCombo(keyCode: 46, modifiers: .command)   // M
        case .openSettings: return KeyCombo(keyCode: 43, modifiers: .command)   // Comma
        case .hidePanel:    return KeyCombo(keyCode: 13, modifiers: .command)   // W
        }
    }

    /// Sidebar-style grouping for the Shortcuts page.
    enum Group: String, CaseIterable {
        case notes = "Notes"
        case editing = "Editing"
        case window = "Window"
    }

    var group: Group {
        switch self {
        case .newNote, .deleteNote, .copyNote, .previousNote, .nextNote, .allNotes:
            return .notes
        case .insertLink, .findInNote:
            return .editing
        case .harborMode, .openSettings, .hidePanel:
            return .window
        }
    }

    /// Shortcuts Buoy will not rebind, shown on the page so it reads as a
    /// complete reference rather than a partial one.
    static let fixed: [(title: String, keys: String)] = [
        ("Bold", "⌘B"),
        ("Italic", "⌘I"),
        ("Underline", "⌘U"),
        ("Strikethrough", "⌘⇧X"),
        ("Select All", "⌘A"),
        ("Copy", "⌘C"),
        ("Paste", "⌘V"),
        ("Cut", "⌘X"),
        ("Undo", "⌘Z"),
        ("Redo", "⌘⇧Z"),
        ("Indent / Outdent list", "⇥ / ⇧⇥")
    ]
}
