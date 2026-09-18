import Foundation
import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.n, modifiers: [.option, .command]))
}

final class HotkeyService {
    static let shared = HotkeyService()
    var onToggle: (() -> Void)?
    private var registeredShortcut: String?
    private var isListening = false

    private init() {}

    func register(shortcut: String? = nil) {
        if let shortcut, !shortcut.isEmpty, shortcut != registeredShortcut {
            updateShortcut(from: shortcut)
            registeredShortcut = shortcut
        }

        guard !isListening else { return }
        isListening = true
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.onToggle?()
        }
    }

    private func updateShortcut(from string: String) {
        guard let combo = KeyCombo(electronString: string) else { return }
        let key = KeyboardShortcuts.Key(rawValue: Int(combo.keyCode))
        KeyboardShortcuts.setShortcut(.init(key, modifiers: combo.modifierFlags), for: .togglePanel)
    }
}
