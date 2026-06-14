import SwiftUI
import AppKit

/// Floating pill that surfaces an available update at the bottom edge of the
/// main panel. Modeled on the SettingsPanel glass + the NotificationToast
/// slide-up transition. Floats over the editor without affecting panel height.
struct UpdateBubble: View {
    let version: String
    var onUpdate: () -> Void
    var onDismiss: () -> Void

    @State private var isUpdateHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text("Buoy v\(version) is available")
                .font(.system(size: 12, weight: .medium))
                .fixedSize()

            Button(action: onUpdate) {
                Text("Update")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .buoyGlassButton(tint: .accentColor, isHovering: isUpdateHovering)
            }
            .buttonStyle(.plain)
            .onHover { isUpdateHovering = $0 }
            .pointingHandCursor()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WindowDragBlocker())
        .overlay(ArrowCursorOverlay().allowsHitTesting(false))
        .buoyGlassPanel(cornerRadius: 14)
        .shadow(radius: 8)
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
                .padding(.bottom, PanelLayoutMetrics.footerOverlayBottomInset)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.16), value: updateInfo?.version)
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
        withAnimation(.easeOut(duration: 0.16)) {
            updateInfo = (version: version, url: url)
        }
    }

    private func openUpdate(_ url: URL) {
        NSWorkspace.shared.open(url)
        withAnimation(.easeOut(duration: 0.16)) { updateInfo = nil }
    }

    private func dismissUpdate(_ version: String) {
        settings.dismissedUpdateVersion = version
        settings.save()
        withAnimation(.easeOut(duration: 0.16)) { updateInfo = nil }
    }
}

private struct UpdateBubblePointingHandCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else if isHovering {
                    NSCursor.pop()
                }
                isHovering = hovering
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
    }
}

private extension View {
    func pointingHandCursor() -> some View {
        modifier(UpdateBubblePointingHandCursorModifier())
    }
}
