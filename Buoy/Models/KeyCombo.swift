import AppKit

/// One keyboard shortcut: a physical key plus its modifiers.
///
/// Stored as a key *code* rather than a character so a binding survives a
/// keyboard-layout change — the key in the same place on the keyboard keeps
/// working, which is what AppKit and every other Mac app do.
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags.rawValue`, already normalized.
    var modifiers: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = Self.normalize(modifiers).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// The comparison every dispatch site has to agree on.
    ///
    /// Caps Lock is dropped rather than matched: a shortcut that stops working
    /// because Caps Lock is on is indistinguishable from a broken app. The
    /// numeric-pad, function and help bits are dropped for the same reason —
    /// they ride along on keys that legitimately carry them (the arrows set
    /// `.function` and `.numericPad`) and would make an exact compare fail.
    static func normalize(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .help, .capsLock])
    }

    /// Built from a key event, or `nil` when it carries no modifier Buoy can
    /// safely claim. Shift alone is not enough — it would swallow typing.
    init?(event: NSEvent) {
        let flags = Self.normalize(event.modifierFlags)
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else {
            return nil
        }
        self.init(keyCode: event.keyCode, modifiers: flags)
    }

    init?(electronString: String) {
        let parts = electronString.split(separator: "+").map(String.init)
        guard let key = parts.last,
              let keyCode = Self.names.first(where: {
                  $0.value.caseInsensitiveCompare(key) == .orderedSame
              })?.key ?? ["space": UInt16(49), "return": 36, "enter": 36, "delete": 51,
                         "backspace": 51, "tab": 48, "escape": 53][key.lowercased()]
        else { return nil }
        var flags: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            switch part.lowercased() {
            case "cmd", "command": flags.insert(.command)
            case "ctrl", "control": flags.insert(.control)
            case "option", "alt": flags.insert(.option)
            case "shift": flags.insert(.shift)
            default: return nil
            }
        }
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else { return nil }
        self.init(keyCode: keyCode, modifiers: flags)
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && Self.normalize(event.modifierFlags) == modifierFlags
    }

    // MARK: Display

    /// `"Option+Cmd+N"`, the form `ShortcutKeyCapsView` already renders and the
    /// form the global hotkey has always been persisted in.
    var electronString: String {
        var parts: [String] = []
        let flags = modifierFlags
        if flags.contains(.control) { parts.append("Ctrl") }
        if flags.contains(.option)  { parts.append("Option") }
        if flags.contains(.shift)   { parts.append("Shift") }
        if flags.contains(.command) { parts.append("Cmd") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: "+")
    }

    /// What a menu item needs: the character AppKit matches on, and the mask.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard let character = Self.menuCharacter(for: keyCode) else { return nil }
        return (character, modifierFlags)
    }

    // MARK: Key tables
    //
    // US layout positions. A different layout puts different characters on
    // these keys, which is the accepted trade for bindings that stay where the
    // user physically put them.

    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N",
        46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8",
        25: "9", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\",
        43: ",", 44: "/", 47: ".", 50: "`",
        36: "⏎", 48: "⇥", 49: "␣", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    /// Characters AppKit wants in `NSMenuItem.keyEquivalent`, which are the
    /// literal characters rather than the glyphs shown to the user.
    private static let menuCharacters: [UInt16: String] = [
        36: "\r", 48: "\t", 49: " ", 51: "\u{8}", 53: "\u{1b}",
        123: "\u{F702}", 124: "\u{F703}", 125: "\u{F701}", 126: "\u{F700}"
    ]

    static func keyName(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    var isSupported: Bool { Self.names[keyCode] != nil }

    private static func menuCharacter(for keyCode: UInt16) -> String? {
        if let special = menuCharacters[keyCode] { return special }
        guard let name = names[keyCode], name.count == 1,
              name.first?.isLetter == true || name.first?.isNumber == true || "=-][';\\,/.`".contains(name) else {
            return nil
        }
        return name.lowercased()
    }
}
