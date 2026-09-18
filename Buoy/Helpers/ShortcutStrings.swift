import AppKit

/// Parsing and formatting for Buoy's Electron-style shortcut strings
/// (`"Option+Cmd+N"`), shared by every recorder and every display.
///
/// Three copies of this logic existed before — `ShortcutRecorderView`, the
/// onboarding welcome slide, and a private helper in `ContentView` — and they
/// had already drifted on which modifiers counted.
enum ShortcutStrings {
    /// Combos macOS claims for itself. Recording one would register a hotkey
    /// that never fires, so it is rejected at the recorder instead.
    static let systemReserved: Set<String> = [
        "Cmd+Space", "Cmd+Tab", "Cmd+Shift+3", "Cmd+Shift+4", "Cmd+Shift+5"
    ]

    /// The modifier set a shortcut must carry to be recordable. Shift alone is
    /// not enough — it would swallow ordinary typing.
    static func hasRequiredModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
    }

    /// Builds the canonical string for a key event, or `nil` when the event
    /// carries no key or no qualifying modifier.
    ///
    /// Modifier order is fixed (`Ctrl+Option+Shift+Cmd+KEY`) so two recordings
    /// of the same combo always compare equal as strings.
    static func electronString(for event: NSEvent) -> String? {
        let mods = event.modifierFlags
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else { return nil }
        guard hasRequiredModifier(mods) else { return nil }

        var parts: [String] = []
        if mods.contains(.control) { parts.append("Ctrl") }
        if mods.contains(.option)  { parts.append("Option") }
        if mods.contains(.shift)   { parts.append("Shift") }
        if mods.contains(.command) { parts.append("Cmd") }
        parts.append(chars.uppercased())
        return parts.joined(separator: "+")
    }

    /// `"Option+Cmd+N"` → `"⌥⌘N"`, for display next to an action name.
    static func symbols(_ shortcut: String) -> String {
        shortcut
            .replacingOccurrences(of: "Cmd",    with: "⌘")
            .replacingOccurrences(of: "Ctrl",   with: "⌃")
            .replacingOccurrences(of: "Option", with: "⌥")
            .replacingOccurrences(of: "Shift",  with: "⇧")
            .replacingOccurrences(of: "+",      with: "")
    }
}
