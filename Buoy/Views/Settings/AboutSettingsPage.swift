import SwiftUI
import AppKit

struct AboutSettingsPage: View {
    var onReportBug: () -> Void
    var onQuit: () -> Void

    @State private var updateStatus: String?
    @State private var updateStatusTask: Task<Void, Never>?

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .accessibilityHidden(true)

                Text("Buoy")
                    .font(.title2.weight(.semibold))

                Text(versionLine)
                    .font(BuoyFont.secondary)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(action: checkForUpdates) {
                        Text(updateStatus ?? "Check for Updates")
                            // Fixed so the row does not jump when the label
                            // swaps to a status line and back.
                            .frame(width: 168)
                    }
                    .accessibilityLabel("Check for Updates")
                    .accessibilityValue(updateStatus ?? "")

                    // Plain text, no symbol: a `Label` makes the button two
                    // points taller than its neighbours and the row of three
                    // stops lining up.
                    Button("Report a Bug", action: onReportBug)

                    Button("Quit Buoy", role: .destructive, action: onQuit)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(.top, 20)
            }
            .padding(.top, 28)

            Spacer(minLength: 20)

            Text("© Gabe Mempin")
                .font(BuoyFont.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .onDisappear { updateStatusTask?.cancel() }
    }

    private func checkForUpdates() {
        updateStatus = "Checking…"
        updateStatusTask?.cancel()
        updateStatusTask = Task { @MainActor in
            let result = await UpdateService.shared.checkForUpdates()
            switch result {
            case .upToDate(let version):
                updateStatus = "Up to date (v\(version))"
            case .available(let version, let url):
                updateStatus = "v\(version) available"
                NSWorkspace.shared.open(url)
            case .error:
                updateStatus = "Couldn't check"
            }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            updateStatus = nil
        }
    }
}
