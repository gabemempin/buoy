import SwiftUI

/// Root of the Settings window: a floating page picker over one glass surface.
///
/// Built from native controls and `Form`, because this is where users arrive
/// expecting System Settings' conventions. The surface itself is Buoy's own
/// glass, so the window belongs to the app rather than being the one flat
/// rectangle in it.
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
        // The bar floats over the page rather than sitting above it, so the
        // window is one surface. The form's own top inset keeps the first row
        // clear of it.
        detail
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .top, spacing: 0) {
                SettingsTopBar(selection: selection, onSelect: onPageChange)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    // The strip around the capsule is the window's grab
                    // handle, since the title bar is behind the content.
                    .frame(maxWidth: .infinity)
                    .background(WindowDragHandle())
            }
            .background(SettingsWindowSurface(theme: theme))
            .environment(\.buoyTheme, theme)
            .tint(theme.accent)
            .onAppear { onPageChange(page) }
            .onChange(of: model.page) { _, newValue in onPageChange(newValue) }
    }

    private var theme: BuoyTheme {
        BuoyTheme(settings: store.value)
    }

    private var selection: Binding<SettingsPage> {
        Binding(
            get: { page },
            set: { model.page = $0 }
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .general:
            GeneralSettingsPage(
                settings: $store.value,
                onReportBug: onReportBug,
                onQuit: onQuit
            )
        case .appearance:
            AppearanceSettingsPage(settings: $store.value)
        case .shortcuts:
            ShortcutsSettingsPage(settings: $store.value)
        }
    }
}

@Observable
final class SettingsWindowModel {
    var page: SettingsPage = .general
}

enum SettingsWindowMetrics {
    static let contentWidth: CGFloat = 540
    static let contentHeight: CGFloat = 520
    /// Resizable, but not to a size where the two colour wheels collide or a
    /// shortcut row's keycaps meet its label.
    static let minimumContentWidth: CGFloat = 500
    static let minimumContentHeight: CGFloat = 400
    /// Forms stop here and centre in whatever is left. A grouped form that
    /// fills a wide window leaves its controls stranded at the far right, a
    /// long way from the labels they belong to.
    static let formMaxWidth: CGFloat = 500
}

/// The window's own surface.
///
/// Liquid Glass on macOS 26, so Settings is made of the same material as the
/// note panel instead of being the one flat rectangle in the app. The window
/// is transparent underneath this; see `SettingsWindowController`.
private struct SettingsWindowSurface: View {
    let theme: BuoyTheme

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else if #available(macOS 26, *) {
                Color.clear.glassEffect(.regular, in: Rectangle())
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .overlay {
            // The same tint as the panel, at a fraction of the strength. This
            // is a window full of text and system controls; it only needs to
            // read as the same app.
            if let tint = theme.tint {
                tint.opacity(min(0.10, theme.tintOpacityFraction * 0.10))
            }
        }
        .ignoresSafeArea()
    }
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
        .frame(maxWidth: SettingsWindowMetrics.formMaxWidth)
        .frame(maxWidth: .infinity)
    }
}
