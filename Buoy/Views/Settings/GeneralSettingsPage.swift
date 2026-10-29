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
            SettingsSection(BuoyWording.behavior) {
                Toggle("Show in Dock", isOn: $settings.showInDock)
                Toggle("Always on Top", isOn: $settings.alwaysOnTop)
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }

            // Shown disabled rather than hidden on a Mac that cannot run it.
            // Hiding the row left anyone who had read about the feature with
            // nowhere to find out why they did not have it; the reason says so.
            SettingsSection("Notes") {
                // Reads as off on a Mac that cannot run it. The stored value
                // is left alone, so moving to a supported Mac keeps the choice.
                Toggle(isOn: autoTitleBinding) {
                    Text("Auto-name New Notes")
                    if let reason = NoteAutoTitler.unsupportedReason {
                        Text(reason)
                    } else {
                        Text("Names a new note on-device once you have written a few lines.")
                    }
                }
                .disabled(!NoteAutoTitler.isSupported)

                Toggle(isOn: $settings.moveCheckedTodosToBottom) {
                    Text("Move Checked To-dos to Bottom")
                    Text("A to-do you check off moves below the ones still to do.")
                }
            }

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
                            // Expanded lettering is wide, and without this the
                            // name broke across two lines as "Buo / y".
                            .lineLimit(1)
                            .fixedSize()
                        Text(versionLine)
                            .font(BuoyFont.secondary)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 5) {
                        SettingsCapsuleButton(
                            updateStatus ?? "Check for Updates",
                            // Fixed so the column does not jump when the label
                            // swaps to a status line and back.
                            width: 120,
                            action: checkForUpdates
                        )
                        .accessibilityLabel("Check for Updates")
                        .accessibilityValue(updateStatus ?? "")

                        SettingsCapsuleButton("Report a Bug", width: 120, action: onReportBug)
                        SettingsCapsuleButton("Quit Buoy", isDestructive: true, width: 120, action: onQuit)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("About Buoy")
            }
        }
        .onDisappear {
            updateStatusTask?.cancel()
            // Otherwise a check cancelled mid-flight leaves "Checking…" up,
            // and the re-entry guard would refuse every later click.
            updateStatus = nil
        }
    }

    private var autoTitleBinding: Binding<Bool> {
        Binding(
            get: { NoteAutoTitler.isSupported && settings.autoTitleEnabled },
            set: { settings.autoTitleEnabled = $0 }
        )
    }

    /// How long "Checking…" stays up even when the answer is instant. A
    /// fast network made it flash for a frame before "Up to date", which
    /// read as a glitch rather than as a check having happened.
    private static let minimumCheckingDuration: Duration = .milliseconds(900)

    private func checkForUpdates() {
        // A second click mid-check would restart the minimum and the result.
        guard updateStatus != "Checking…" else { return }
        setUpdateStatus("Checking…")
        updateStatusTask?.cancel()
        updateStatusTask = Task { @MainActor in
            let started = ContinuousClock.now
            let result = await UpdateService.shared.checkForUpdates()
            try? await Task.sleep(until: started + Self.minimumCheckingDuration, clock: .continuous)
            guard !Task.isCancelled else { return }
            switch result {
            case .upToDate(let version):
                setUpdateStatus("Up to date (v\(version))")
            case .available(let version, let url):
                setUpdateStatus("v\(version) available")
                NSWorkspace.shared.open(url)
            case .error:
                setUpdateStatus("Couldn't check")
            }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            setUpdateStatus(nil)
        }
    }

    /// Crossfades the button's label (see `SettingsCapsuleButton`).
    private func setUpdateStatus(_ status: String?) {
        withAnimation(.easeInOut(duration: 0.2)) { updateStatus = status }
    }
}
