import SwiftUI

/// The sections of the Settings window, in sidebar order.
enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:    return "General"
        case .appearance: return "Appearance"
        case .shortcuts:  return "Shortcuts"
        case .about:      return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general:    return "gearshape"
        case .appearance: return "paintpalette"
        case .shortcuts:  return "keyboard"
        case .about:      return "info.circle"
        }
    }

    /// The tile behind the sidebar glyph. System Settings gives every row a
    /// coloured tile rather than a bare symbol, which is what keeps a short
    /// sidebar from reading as a plain list of words.
    var tileColor: Color {
        switch self {
        case .general:    return .gray
        case .appearance: return .pink
        case .shortcuts:  return .indigo
        case .about:      return .blue
        }
    }
}

/// A sidebar row: coloured tile, white glyph, title.
struct SettingsSidebarLabel: View {
    let page: SettingsPage

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .fill(page.tileColor)
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: page.symbolName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }
            Text(page.title)
                .font(BuoyFont.control)
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(page.title)
    }
}
