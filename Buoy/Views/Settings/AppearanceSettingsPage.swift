import SwiftUI

struct AppearanceSettingsPage: View {
    @Binding var settings: AppSettings

    private var defaultFontSize: CGFloat { AppSettings().fontSize }

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

            Section(BuoyWording.colors) {
                HStack(alignment: .top, spacing: 24) {
                    ColorPickerColumn(
                        title: "Window \(BuoyWording.colorLowercased)",
                        selection: $settings.windowTint,
                        intensity: $settings.windowTintIntensity,
                        defaultName: "None",
                        brightness: 1
                    )
                    ColorPickerColumn(
                        title: "Accent \(BuoyWording.colorLowercased)",
                        selection: $settings.accentColor,
                        intensity: nil,
                        defaultName: "System accent",
                        // Held just short of full so an accent never blows out
                        // the text sitting on it.
                        brightness: 0.92
                    )
                }
                .padding(.vertical, 4)
            }

            Section("Text") {
                LabeledContent("Editor text size") {
                    HStack(spacing: 10) {
                        EditorFontSizeSlider(
                            value: $settings.fontSize,
                            defaultValue: defaultFontSize
                        )
                        Text("\(Int(settings.fontSize)) pt")
                            .font(BuoyFont.secondary)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                Text("Text scales down on its own while the panel is small enough for Compact Mode.")
                    .font(BuoyFont.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The size slider, with a dot under the default.
///
/// The marker is the only thing that says where "normal" is. Without it the
/// slider is a bare range and there is no way to get back to the size the app
/// shipped with except by counting.
private struct EditorFontSizeSlider: View {
    @Binding var value: CGFloat
    let defaultValue: CGFloat

    private let range: ClosedRange<CGFloat> = 11...20
    private let width: CGFloat = 150

    private var defaultFraction: CGFloat {
        (defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(spacing: 2) {
            Slider(value: $value, in: range, step: 1)
                .controlSize(.small)
                .accessibilityLabel("Editor text size")
                .accessibilityValue("\(Int(value)) points")

            // The knob is inset by half its width at each end, so the track the
            // marker has to line up with is narrower than the control.
            GeometryReader { proxy in
                let inset: CGFloat = 9
                let usable = max(0, proxy.size.width - inset * 2)
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .offset(x: inset + usable * defaultFraction - 2)
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .frame(width: width)
    }
}
