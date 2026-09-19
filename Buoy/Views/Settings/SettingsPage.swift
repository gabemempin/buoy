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

/// The window's page picker: one glass capsule floating over the content.
///
/// It sits *on* the page rather than in a bar of its own. A full-width strip
/// with a divider under it gave three short words the weight of a toolbar, and
/// left a band of empty space either side of them for no reason.
struct SettingsTopBar: View {
    @Binding var selection: SettingsPage
    var onSelect: (SettingsPage) -> Void

    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsPage.allCases) { page in
                SettingsTopBarItem(
                    page: page,
                    isSelected: selection == page,
                    namespace: selectionNamespace
                ) {
                    guard selection != page else { return }
                    withAnimation(BuoyMotion.spring(response: 0.3, dampingFraction: 0.82)) {
                        selection = page
                    }
                    onSelect(page)
                }
            }
        }
        .padding(4)
        .buoyGlassCapsule()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }
}

private struct SettingsTopBarItem: View {
    let page: SettingsPage
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: page.symbolName)
                    .font(.system(size: 11, weight: .medium))
                Text(page.title)
                    .font(BuoyFont.control)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    // Matched so the pill slides between tabs instead of
                    // blinking out of one and into the next.
                    Capsule()
                        .fill(Color.buoySegmentSelection)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if isHovering {
                    Capsule().fill(Color.buoyControlFill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
