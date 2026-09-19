import SwiftUI

struct AppearanceSettingsPage: View {
    @Binding var settings: AppSettings

    private var defaultFontSize: CGFloat { AppSettings().fontSize }

    var body: some View {
        SettingsForm {
            SettingsSection("Theme") {
                // Centred rather than pinned to the trailing edge. It is the
                // only control in its section and the widest thing on the
                // page; hard against the right it read as an afterthought.
                BuoySegmentedPicker(
                    selection: $settings.theme,
                    options: [
                        .init(value: .system, title: "Auto"),
                        .init(value: .light, title: "Light"),
                        .init(value: .dark, title: "Dark")
                    ],
                    accessibilityLabel: "Appearance"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
            }

            SettingsSection(BuoyWording.colors) {
                HStack(alignment: .top, spacing: 16) {
                    ColorPickerColumn(
                        title: "Window \(BuoyWording.colorLowercased)",
                        selection: $settings.windowTint,
                        defaultName: "None",
                        defaultLightness: 0.5
                    )
                    ColorPickerColumn(
                        title: "Accent \(BuoyWording.colorLowercased)",
                        selection: $settings.accentColor,
                        defaultName: "System accent",
                        defaultLightness: 0.46
                    )
                }
                .padding(.vertical, 2)

                LabeledContent("Window \(BuoyWording.colorLowercased) opacity") {
                    Slider(value: $settings.windowTintOpacity, in: 0...1)
                        // The same lane as the text-size slider below, so the
                        // two read as one column rather than two guesses.
                        .frame(width: SettingsPopoverMetrics.sliderWidth)
                        .disabled(settings.windowTint == nil)
                        .accessibilityLabel("Window \(BuoyWording.colorLowercased) opacity")
                        .accessibilityValue("\(Int(settings.windowTintOpacity * 100)) percent")
                }
            }

            SettingsSection("Text") {
                LabeledContent("Editor text size") {
                    EditorFontSizeSlider(
                        value: $settings.fontSize,
                        defaultValue: defaultFontSize
                    )
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
/// slider is a bare range and there is no way back to the size the app shipped
/// with except by counting.
private struct EditorFontSizeSlider: View {
    @Binding var value: CGFloat
    let defaultValue: CGFloat

    private let range: ClosedRange<CGFloat> = 11...20
    /// The knob's own width, which the track is inset by at each end. The
    /// marker has to use the same inset or it lines up with nothing.
    private let knobWidth: CGFloat = 20

    /// Rounds to whole points on the way in, so the value still steps even
    /// though the slider itself is continuous.
    private var snapped: Binding<CGFloat> {
        Binding(
            get: { value },
            set: { value = $0.rounded() }
        )
    }

    private var defaultFraction: CGFloat {
        (defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 3) {
                // Default control size, not `.small`. A short slider next to
                // full-height rows reads as a disabled or secondary control.
                // No `step:` — it draws a tick under every whole point, which
                // buries the one tick that means something.
                Slider(value: snapped, in: range)
                    .accessibilityLabel("Editor text size")
                    .accessibilityValue("\(Int(value)) points")

                GeometryReader { proxy in
                    let usable = max(0, proxy.size.width - knobWidth)
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 4, height: 4)
                        .offset(x: knobWidth / 2 + usable * defaultFraction - 2)
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
            .frame(width: SettingsPopoverMetrics.sliderWidth)

            Text("\(Int(value)) pt")
                .font(BuoyFont.secondary)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
