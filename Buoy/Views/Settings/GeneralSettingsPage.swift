import SwiftUI

struct GeneralSettingsPage: View {
    @Binding var settings: AppSettings

    var body: some View {
        SettingsForm {
            Section("Behaviour") {
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
        }
        .accessibilityLabel("General settings")
    }
}
