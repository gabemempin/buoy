import SwiftUI

struct AppearanceSettingsPage: View {
    @Binding var settings: AppSettings

    var body: some View {
        SettingsForm {
            Section("Theme") {
                Picker("Appearance", selection: $settings.theme) {
                    Text("Auto").tag(AppTheme.system)
                    Text("Light").tag(AppTheme.light)
                    Text("Dark").tag(AppTheme.dark)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            Section("Colours") {
                ColorWheelRow(
                    title: "Window colour",
                    selection: $settings.windowTint,
                    intensity: $settings.windowTintIntensity,
                    defaultName: "None",
                    brightness: 1
                )
                ColorWheelRow(
                    title: "Accent colour",
                    selection: $settings.accentColor,
                    intensity: nil,
                    defaultName: "System accent",
                    // Held just short of full so an accent never blows out
                    // white text sitting on it.
                    brightness: 0.92
                )
            }

            Section("Layout") {
                Toggle(isOn: $settings.compactChrome) {
                    Text("Compact controls")
                    Text("Smaller buttons and title. Turns on by itself when the panel is short.")
                }
            }

            Section("Text") {
                LabeledContent("Editor text size") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.fontSize, in: 11...20, step: 1)
                            .frame(width: 180)
                            .accessibilityLabel("Editor text size")
                            .accessibilityValue("\(Int(settings.fontSize)) points")
                        Text("\(Int(settings.fontSize)) pt")
                            .font(BuoyFont.secondary)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .accessibilityLabel("Appearance settings")
    }
}
