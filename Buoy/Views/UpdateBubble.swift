import SwiftUI
import AppKit

/// The update notice: a `NotificationToast` that stays until it is acted on
/// or dismissed, so it looks and moves exactly like every other lower-center
/// pill. Floats over the editor without affecting panel height.
struct UpdateBubble: View {
    let version: String
    var onUpdate: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        NotificationToast(
            message: "Buoy \(version) is available",
            symbolName: "arrow.up.circle.fill",
            action: ToastAction(title: "Update", handler: onUpdate),
            onClose: onDismiss
        )
    }
}

/// Self-contained overlay that owns the periodic update check and renders the
/// bubble. Kept separate from ContentView so the bubble's view logic doesn't
/// inflate ContentView.body past the Swift type-checker's time budget.
struct UpdateBubbleOverlay: View {
    @Binding var settings: AppSettings
    /// When true (another overlay/mode owns the bottom edge), the bubble is hidden.
    let isSuppressed: Bool

    @State private var updateInfo: (version: String, url: URL)? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            if let update = updateInfo, !isSuppressed {
                UpdateBubble(
                    version: update.version,
                    onUpdate: { openUpdate(update.url) },
                    onDismiss: { dismissUpdate(update.version) }
                )
                .padding(.bottom, PanelLayoutMetrics.footerPillBottomPadding)
                .transition(BuoyMotion.pillPop)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(BuoyMotion.pillAnimation, value: updateInfo?.version)
        .animation(BuoyMotion.pillAnimation, value: isSuppressed)
        .task {
            // Auto-check at launch, then re-check daily while the app stays running.
            while !Task.isCancelled {
                await checkForUpdate()
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }

    @MainActor
    private func checkForUpdate() async {
        let result = await UpdateService.shared.checkForUpdates()
        guard case let .available(version, url) = result else { return }
        guard version != settings.dismissedUpdateVersion else { return }
        withAnimation(BuoyMotion.pillAnimation) {
            updateInfo = (version: version, url: url)
        }
    }

    private func openUpdate(_ url: URL) {
        NSWorkspace.shared.open(url)
        withAnimation(BuoyMotion.pillAnimation) { updateInfo = nil }
    }

    private func dismissUpdate(_ version: String) {
        settings.dismissedUpdateVersion = version
        settings.save()
        withAnimation(BuoyMotion.pillAnimation) { updateInfo = nil }
    }
}

