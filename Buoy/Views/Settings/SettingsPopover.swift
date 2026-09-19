import SwiftUI

/// Settings, as a popover on the footer's gear.
///
/// It was a window for a while: first with a sidebar, then a top bar, then a
/// child window that followed the panel around. All of that was working
/// against the shape of the app. Buoy is one floating panel, and its other
/// secondary surfaces — the link editor, Transfer to Apple Notes — are
/// popovers anchored to the control that opens them. A popover inherits all
/// the behaviour the window was being taught by hand: it points at its button,
/// it moves with the panel because it is attached to it, it closes when you
/// click away, and the panel keeps its focused appearance underneath.
struct SettingsPopover: View {
    @Binding var settings: AppSettings
    var onReportBug: () -> Void
    var onQuit: () -> Void

    @State private var page: SettingsPage = .general

    private var theme: BuoyTheme {
        BuoyTheme(settings: settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            BuoySegmentedPicker(
                selection: $page,
                options: SettingsPage.allCases.map {
                    .init(value: $0, title: $0.title, symbolName: $0.symbolName)
                },
                accessibilityLabel: "Settings sections"
            )
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            content
        }
        .frame(width: SettingsPopoverMetrics.width, height: SettingsPopoverMetrics.height)
        .environment(\.buoyTheme, theme)
        .tint(theme.accent)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .general:
            GeneralSettingsPage(
                settings: $settings,
                onReportBug: onReportBug,
                onQuit: onQuit
            )
        case .appearance:
            AppearanceSettingsPage(settings: $settings)
        case .shortcuts:
            ShortcutsSettingsPage(settings: $settings)
        }
    }
}

enum SettingsPopoverMetrics {
    static let width: CGFloat = 420
    static let height: CGFloat = 430
    /// One lane for every slider in here.
    static let sliderWidth: CGFloat = 150
}

/// Shared page shell.
///
/// `.grouped` rather than the popover's plain default, so sections read as
/// sections; the background is dropped because the popover already supplies
/// one and a second surface inside it looks like a panel in a panel.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
