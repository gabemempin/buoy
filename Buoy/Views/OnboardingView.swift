import SwiftUI

struct OnboardingView: View {
    @Binding var settings: AppSettings
    var onShortcutChanged: (String) -> Void

    var body: some View {
        ZStack {
            // Background
            if #available(macOS 26, *) {
                Color.clear
                    .floatNotesGlass()
            } else {
                VisualEffectBackground(material: .menu, blendingMode: .behindWindow)
            }

            VStack(spacing: 16) {
                // App icon
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(radius: 4)
                }

                // Title
                VStack(spacing: 6) {
                    Text("Welcome to Buoy")
                        .font(.system(size: 18, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("A floating notepad that lives in your menu bar.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Feature pills
                VStack(spacing: 8) {
                    FeaturePill(icon: "arrow.up.left.and.arrow.down.right", text: "Always on top of other windows")
                    FeaturePill(icon: "arrow.clockwise", text: "Notes saved automatically")
                    FeaturePill(icon: "keyboard", text: "Toggle with a global shortcut")
                }

                Divider().padding(.horizontal, 24)

                // Shortcut recorder
                VStack(spacing: 8) {
                    Text("Global Shortcut")
                        .font(.system(size: 12, weight: .medium))
                    ShortcutRecorderView(shortcut: $settings.globalShortcut, onChanged: onShortcutChanged)
                }

                // CTA
                Button {
                    settings.onboarded = true
                    settings.save()
                } label: {
                    Text("Get Started")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
            }
            .padding(24)
        }
        .frame(width: 380)
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
        .background(Color.primary.opacity(0.05))
        .clipShape(Capsule())
    }
}
