import SwiftUI
import AppKit

struct GeneralSettingsPage: View {
    @Binding var settings: AppSettings
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
        SettingsForm {
            Section(BuoyWording.behavior) {
                Toggle("Show in Dock", isOn: $settings.showInDock)
                Toggle("Always on Top", isOn: $settings.alwaysOnTop)
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }

            // Shown disabled rather than hidden on a Mac that cannot run it.
            // Hiding the row left anyone who had read about the feature with
            // nowhere to find out why they did not have it; the reason says so.
            Section("Notes") {
                Toggle(isOn: $settings.autoTitleEnabled) {
                    Text("Auto-name New Notes")
                    if let reason = NoteAutoTitler.unsupportedReason {
                        Text(reason)
                    } else {
                        Text("Names a new note on-device once you have written a few lines.")
                    }
                }
                .disabled(!NoteAutoTitler.isSupported)
            }

            // About lived on its own page while there was a sidebar to hang it
            // from. It is four lines; with three tabs across the top it reads
            // better as the last section here than as a tab of its own.
            // About lived on its own page while there was a sidebar to hang it
            // from. It is the app's name and three buttons; with three tabs
            // across the top it reads better as the last section here.
            Section {
                HStack(alignment: .center, spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Buoy")
                            // The note title's face. It is the app's name in
                            // the app's own lettering, not a form label.
                            .font(Font(PanelLayoutMetrics.minimizedTitleFont))
                        Text(versionLine)
                            .font(BuoyFont.secondary)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 5) {
                        Button(action: checkForUpdates) {
                            // Fixed so the column does not jump when the label
                            // swaps to a status line and back.
                            Text(updateStatus ?? "Check for Updates").frame(width: 128)
                        }
                        .accessibilityLabel("Check for Updates")
                        .accessibilityValue(updateStatus ?? "")

                        Button("Report a Bug", action: onReportBug)
                            .frame(width: 128)
                        Button("Quit Buoy", role: .destructive, action: onQuit)
                            .frame(width: 128)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("About Buoy")
            }
        }
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
