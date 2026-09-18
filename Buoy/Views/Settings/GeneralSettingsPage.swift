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

            // Hidden outright rather than shown-disabled: auto-naming only ever
            // applies on Apple Silicon Macs with Apple Intelligence on, and a
            // permanently greyed row is a worse answer than no row.
            if NoteAutoTitler.isSupported {
                Section("Notes") {
                    Toggle(isOn: $settings.autoTitleEnabled) {
                        Text("Auto-name New Notes")
                        Text("Names a new note on-device once you have written a few lines.")
                    }
                }
            }

            // About lived on its own page while there was a sidebar to hang it
            // from. It is four lines; with three tabs across the top it reads
            // better as the last section here than as a tab of its own.
            Section("About") {
                LabeledContent("Buoy") {
                    Text(versionLine)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button(action: checkForUpdates) {
                        // Fixed so the row does not jump when the label swaps
                        // to a status line and back.
                        Text(updateStatus ?? "Check for Updates").frame(width: 152)
                    }
                    .accessibilityLabel("Check for Updates")
                    .accessibilityValue(updateStatus ?? "")

                    Button("Report a Bug", action: onReportBug)
                    Button("Quit Buoy", role: .destructive, action: onQuit)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
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
