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

}

/// The window's page picker: one segmented control across the top.
///
/// Tried as a sidebar first, then as a row of coloured tiles. Both were more
/// furniture than three pages need — a settings window with this little in it
/// should not open with a navigation column. A segmented control says "these
/// are the three views" in one object, and it is the control macOS already
/// uses for exactly this.
struct SettingsTopBar: View {
    @Binding var selection: SettingsPage
    var onSelect: (SettingsPage) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SettingsPage.allCases) { page in
                SettingsTopBarItem(page: page, isSelected: selection == page) {
                    guard selection != page else { return }
                    selection = page
                    onSelect(page)
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.buoySegmentTrack))
        .animation(BuoyMotion.easeInOut(0.15), value: selection)
        // Centred in the window rather than inset past the traffic lights: the
        // pill is far narrower than the window, so the lights never reach it.
        .frame(maxWidth: .infinity)
        .frame(height: SettingsWindowMetrics.topBarHeight)
        // The strip doubles as the window's grab handle, since the title bar
        // is behind it.
        .background(WindowDragHandle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }
}

private struct SettingsTopBarItem: View {
    let page: SettingsPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(page.title)
                .font(BuoyFont.control)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        Capsule().fill(Color.buoySegmentSelection)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
