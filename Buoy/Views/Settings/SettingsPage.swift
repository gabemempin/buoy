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

/// The window's page picker, across the top.
///
/// A sidebar was tried first and gave the pages a permanent 190pt column to
/// live beside, which the content then had to squeeze into — the colour rows
/// in particular. Across the top it costs 52pt once and every page gets the
/// full width.
struct SettingsTopBar: View {
    @Binding var selection: SettingsPage
    var onSelect: (SettingsPage) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsPage.allCases) { page in
                SettingsTopBarItem(page: page, isSelected: selection == page) {
                    selection = page
                    onSelect(page)
                }
            }
            Spacer(minLength: 0)
        }
        // Clears the traffic lights, which sit in this same strip because the
        // window draws its content under the title bar.
        .padding(.leading, 78)
        .padding(.trailing, 12)
        .frame(height: SettingsWindowMetrics.topBarHeight)
        // The strip is the window's only grab handle now that the title bar is
        // behind it.
        .background(WindowDragHandle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }
}

private struct SettingsTopBarItem: View {
    let page: SettingsPage
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(page.tileColor)
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: page.symbolName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                    }
                Text(page.title)
                    .font(BuoyFont.control)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fill)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var fill: Color {
        if isSelected { return .buoySelectionFill }
        return isHovering ? .buoyControlFill : .clear
    }
}
