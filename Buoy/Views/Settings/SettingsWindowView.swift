import SwiftUI

/// Root of the Settings window: sidebar on the left, one page on the right.
///
/// Deliberately built from native controls and `Form`. Buoy's glass belongs to
/// the note panel; a settings window that tried to wear it would read as a
/// second, competing surface — and it is the one place in the app where users
/// arrive expecting System Settings' conventions, not Buoy's.
struct SettingsWindowView: View {
    @Bindable var store: SettingsStore
    /// Holds the selected page outside the view so the window controller can
    /// open Settings straight onto a given page (the footer's keyboard button
    /// opens Shortcuts) without reaching into SwiftUI state.
    @Bindable var model: SettingsWindowModel
    var onPageChange: (SettingsPage) -> Void
    var onReportBug: () -> Void
    var onQuit: () -> Void

    private var page: SettingsPage { model.page }

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: selection) { item in
                SettingsSidebarLabel(page: item)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .frame(width: SettingsWindowMetrics.sidebarWidth)
            // Pinned rather than given as an ideal: `.balanced` otherwise
            // picks its own width and lands well under the rows' needs.
            .navigationSplitViewColumnWidth(
                min: SettingsWindowMetrics.sidebarWidth,
                ideal: SettingsWindowMetrics.sidebarWidth,
                max: SettingsWindowMetrics.sidebarWidth
            )
            // The sidebar is the window's only navigation and every page is
            // one click away, so a collapse control would only ever hide it by
            // mistake. Applied to the sidebar's own content, which is where
            // SwiftUI looks for it — on the split view itself it is ignored.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .top
                )
                .background(detailBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.buoyTheme, theme)
        .tint(theme.accent)
        .onAppear { onPageChange(page) }
        .onChange(of: model.page) { _, newValue in onPageChange(newValue) }
    }

    private var theme: BuoyTheme {
        BuoyTheme(settings: store.value)
    }

    /// The window background, plus the user's tint if they picked one — kept
    /// far weaker than on the panel. This is a settings window full of text and
    /// system controls, and it only needs to read as the same app.
    private var detailBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay {
                if let tint = theme.tint {
                    tint.opacity(min(0.10, theme.tintIntensity * 0.10))
                }
            }
            .ignoresSafeArea()
    }

    private var selection: Binding<SettingsPage> {
        Binding(
            get: { page },
            set: { newValue in
                model.page = newValue
                onPageChange(newValue)
            }
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .general:
            GeneralSettingsPage(settings: $store.value)
        case .appearance:
            AppearanceSettingsPage(settings: $store.value)
        case .shortcuts:
            ShortcutsSettingsPage(settings: $store.value)
        case .about:
            AboutSettingsPage(onReportBug: onReportBug, onQuit: onQuit)
        }
    }
}

@Observable
final class SettingsWindowModel {
    var page: SettingsPage = .general
}

enum SettingsWindowMetrics {
    static let sidebarWidth: CGFloat = 190
    static let contentWidth: CGFloat = 720
    static let contentHeight: CGFloat = 500
}

/// Shared page shell: a grouped `Form` with the window background showing
/// through, so every page lines up and nothing invents its own chrome.
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
