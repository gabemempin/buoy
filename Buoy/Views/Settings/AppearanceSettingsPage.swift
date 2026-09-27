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
                    DefaultMarkedSlider(
                        value: $settings.windowTintOpacity,
                        range: 0...1,
                        defaultValue: AppSettings().windowTintOpacity
                    )
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

/// Appearance slider with the default value marked and slightly magnetic.
///
/// On macOS 26 the mark is the system's own slider tick (`SliderTick`), so it
/// sits exactly under the knob's travel, dims with the control and matches
/// every other slider on the Mac. Earlier systems have no API for a single
/// tick, so they keep a small drawn dot.
private struct DefaultMarkedSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    var roundsToWholePoints = false

    private var snapped: Binding<Double> {
        Binding(
            get: { value },
            set: { proposed in
                // Two percent of the track gives the default a small landing
                // zone while leaving the rest of the range continuous.
                let tolerance = (range.upperBound - range.lowerBound) * 0.02
                if abs(proposed - defaultValue) <= tolerance {
                    value = defaultValue
                } else {
                    value = roundsToWholePoints ? proposed.rounded() : proposed
                }
            }
        )
    }

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                // No `step`: it would put a tick at every value, not just the default.
                Slider(
                    value: snapped,
                    in: range,
                    label: { EmptyView() },
                    minimumValueLabel: { EmptyView() },
                    maximumValueLabel: { EmptyView() },
                    ticks: { SliderTick(defaultValue) }
                )
                .labelsHidden()
            } else {
                LegacyDefaultMarkedSlider(value: snapped, range: range, defaultValue: defaultValue)
            }
        }
        .frame(width: SettingsPopoverMetrics.sliderWidth)
    }
}

/// macOS 15: a dot under the track at the default.
private struct LegacyDefaultMarkedSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double

    @Environment(\.isEnabled) private var isEnabled
    private let knobWidth: CGFloat = 20

    var body: some View {
        VStack(spacing: 3) {
            Slider(value: $value, in: range)
            GeometryReader { proxy in
                let usable = max(0, proxy.size.width - knobWidth)
                let fraction = CGFloat((defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound))
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .offset(x: knobWidth / 2 + usable * fraction - 2)
            }
            .frame(height: 4)
            .opacity(isEnabled ? 1 : 0.4)
            .accessibilityHidden(true)
        }
    }
}

private struct EditorFontSizeSlider: View {
    @Binding var value: CGFloat
    let defaultValue: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            DefaultMarkedSlider(
                value: Binding(get: { Double(value) }, set: { value = CGFloat($0) }),
                range: 11...20,
                defaultValue: Double(defaultValue),
                roundsToWholePoints: true
            )
            .accessibilityLabel("Editor text size")
            .accessibilityValue("\(Int(value)) points")

            Text("\(Int(value)) pt")
                .font(BuoyFont.secondary)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
