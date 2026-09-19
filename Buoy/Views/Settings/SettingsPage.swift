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

/// The window's page picker: a glass segmented control floating over the page.
///
/// It sits *on* the page rather than in a bar of its own. A full-width strip
/// with a divider under it gave three short words the weight of a toolbar, and
/// left a band of empty space either side of them for no reason.
struct SettingsTopBar: View {
    @Binding var selection: SettingsPage
    var onSelect: (SettingsPage) -> Void

    var body: some View {
        BuoySegmentedPicker(
            selection: Binding(
                get: { selection },
                set: { newValue in
                    selection = newValue
                    onSelect(newValue)
                }
            ),
            options: SettingsPage.allCases.map {
                .init(value: $0, title: $0.title, symbolName: $0.symbolName)
            },
            accessibilityLabel: "Settings sections"
        )
    }
}
