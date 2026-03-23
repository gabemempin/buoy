import Foundation
import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.n, modifiers: [.option, .command]))
}

final class HotkeyService {
    static let shared = HotkeyService()
    var onToggle: (() -> Void)?

    private init() {}

    func register(shortcut: String? = nil) {
        // If a shortcut string is provided, update it
        if let shortcut, !shortcut.isEmpty {
            updateShortcut(from: shortcut)
        }

        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.onToggle?()
        }
    }

    private func updateShortcut(from string: String) {
        // Map from Electron-style "Option+Cmd+N" to KeyboardShortcuts.Shortcut
        var mods: NSEvent.ModifierFlags = []
        var key: KeyboardShortcuts.Key?

        let parts = string.components(separatedBy: "+")
        for part in parts {
            switch part.lowercased() {
            case "cmd", "command": mods.insert(.command)
            case "ctrl", "control": mods.insert(.control)
            case "option", "alt": mods.insert(.option)
            case "shift": mods.insert(.shift)
            default:
                if let k = KeyboardShortcuts.Key(string: part.lowercased()) {
                    key = k
                } else if part.count == 1, let c = part.lowercased().first {
                    key = KeyboardShortcuts.Key(string: String(c))
                }
            }
        }

        if let key {
            KeyboardShortcuts.setShortcut(.init(key, modifiers: mods), for: .togglePanel)
        }
    }
}

private extension KeyboardShortcuts.Key {
    init?(string: String) {
        switch string {
        case "a": self = .a
        case "b": self = .b
        case "c": self = .c
        case "d": self = .d
        case "e": self = .e
        case "f": self = .f
        case "g": self = .g
        case "h": self = .h
        case "i": self = .i
        case "j": self = .j
        case "k": self = .k
        case "l": self = .l
        case "m": self = .m
        case "n": self = .n
        case "o": self = .o
        case "p": self = .p
        case "q": self = .q
        case "r": self = .r
        case "s": self = .s
        case "t": self = .t
        case "u": self = .u
        case "v": self = .v
        case "w": self = .w
        case "x": self = .x
        case "y": self = .y
        case "z": self = .z
        case "0": self = .zero
        case "1": self = .one
        case "2": self = .two
        case "3": self = .three
        case "4": self = .four
        case "5": self = .five
        case "6": self = .six
        case "7": self = .seven
        case "8": self = .eight
        case "9": self = .nine
        case "return", "enter": self = .return
        case "space": self = .space
        case "delete", "backspace": self = .delete
        case "escape": self = .escape
        default: return nil
        }
    }
}
