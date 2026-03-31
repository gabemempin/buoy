import SwiftUI

struct OnboardingView: View {
    @Binding var settings: AppSettings
    var onShortcutChanged: (String) -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Background
            Color.clear
                .buoyInsetGlass(
                    inset: PanelLayoutMetrics.onboardingInset,
                    cornerRadius: PanelLayoutMetrics.onboardingCornerRadius
                )

            VStack(spacing: 16) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(radius: 3)
                }

                VStack(spacing: 6) {
                    Text("Welcome to Buoy")
                        .font(.system(size: 23, weight: .bold))
                        .fontWidth(.expanded)
                        .multilineTextAlignment(.center)
                    Text("A notepad that's always there on top of all your windows.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 8) {
                    FeaturePill(icon: "arrow.up.left.and.arrow.down.right", text: "Always on top of other windows")
                    FeaturePill(icon: "arrow.clockwise", text: "Notes saved automatically")
                    FeaturePill(icon: "keyboard", text: "Toggle with a global shortcut")
                }

                Divider().padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    Text("Set a shortcut to quickly open Buoy from anywhere, or keep the default")
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .tracking(-0.2)
                    ShortcutRecorderView(shortcut: $settings.globalShortcut, onChanged: onShortcutChanged)
                }

                Button {
                    settings.onboarded = true
                    settings.save()
                    onDismiss()
                } label: {
                    Text("Get Started")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)
            }
            .padding(24)
            .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FeaturePill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(width: 240)
        .background(Color.primary.opacity(0.05))
        .clipShape(Capsule())
    }
}
