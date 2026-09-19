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
        // The popover wears the window colour too. It is the surface the
        // colour is being chosen on, and a neutral one sitting against a
        // tinted panel made the choice harder to judge, not easier.
        .background {
            if let tint = theme.tint {
                tint.opacity(theme.tintOpacity)
            }
        }
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
    static let width: CGFloat = 360
    static let height: CGFloat = 420
    /// Gap between the gear and the popover's arrow, so the two are not
    /// welded together. `.popover` has no offset of its own, so the anchor
    /// rect is widened by this instead.
    static let anchorGap: CGFloat = 10
    /// One lane for every slider in here.
    static let sliderWidth: CGFloat = 120
}

/// A form section whose heading actually reads as one.
///
/// A grouped `Form` on macOS draws its section headers *smaller* than the row
/// labels underneath them, which leaves the heading looking like a caption on
/// the section above it. This sets the header a size up and a weight heavier
/// than the rows, so the hierarchy runs the way it looks like it should.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        Section {
            content()
        } header: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
                .padding(.bottom, 1)
        }
    }
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
        // Only the control size. A blanket `.font` here also lands on the
        // section headers and flattens them to the weight of a row label,
        // which is the hierarchy it was meant to fix. Rows that need a smaller
        // label set it themselves.
        .controlSize(.small)
    }
}
