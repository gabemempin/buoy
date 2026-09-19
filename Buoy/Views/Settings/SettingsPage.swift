import SwiftUI

/// The sections of the Settings window, in sidebar order.
enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:    return "General"
        case .appearance: return "Appearance"
        case .shortcuts:  return "Shortcuts"
        }
    }

    var symbolName: String {
        switch self {
        case .general:    return "gearshape"
        case .appearance: return "paintpalette"
        case .shortcuts:  return "keyboard"
        }
    }
}
