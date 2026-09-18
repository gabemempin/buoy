import SwiftUI
import AppKit

/// Picks a hue and saturation with two horizontal strips and a row of presets.
///
/// A wheel came first and read well, but it is a tall square control and there
/// are two of them side by side in a window that should be small. Strips carry
/// the same two values in a third of the height, and the presets mean the
/// common case — "make it blue" — is one click rather than a drag.
struct ColorStripPicker: View {
    @Binding var selection: HSBColor?
    /// Brightness is fixed by the caller rather than exposed. A third axis
    /// would make this a colour *editor*; what is being chosen is a hue.
    let brightness: Double

    private static let presetHues: [Double] = [
        0.0, 0.07, 0.13, 0.33, 0.48, 0.58, 0.70, 0.83
    ]
    private static let presetSaturation: Double = 0.68
    private static let stripHeight: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            presets

            VStack(alignment: .leading, spacing: 6) {
                strip(
                    gradient: LinearGradient(colors: hueStops, startPoint: .leading, endPoint: .trailing),
                    value: selection?.hue ?? 0,
                    isEnabled: true,
                    label: "Hue"
                ) { fraction in
                    let current = selection
                    selection = HSBColor(
                        hue: fraction,
                        saturation: current?.saturation ?? Self.presetSaturation,
                        brightness: current?.brightness ?? brightness
                    )
                }

                strip(
                    gradient: LinearGradient(
                        colors: [
                            Color(hue: selection?.hue ?? 0, saturation: 0, brightness: brightness),
                            Color(hue: selection?.hue ?? 0, saturation: 1, brightness: brightness)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    value: selection?.saturation ?? 0,
                    isEnabled: selection != nil,
                    label: "Saturation"
                ) { fraction in
                    guard let current = selection else { return }
                    selection = HSBColor(
                        hue: current.hue,
                        saturation: fraction,
                        brightness: current.brightness
                    )
                }
            }
        }
    }

    private var hueStops: [Color] {
        (0...12).map { Color(hue: Double($0) / 12, saturation: 0.75, brightness: brightness) }
    }

    private var presets: some View {
        HStack(spacing: 6) {
            ForEach(Self.presetHues, id: \.self) { hue in
                let swatch = HSBColor(
                    hue: hue,
                    saturation: Self.presetSaturation,
                    brightness: brightness
                )
                Button { selection = swatch } label: {
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle().strokeBorder(
                                isChosen(swatch) ? Color.primary : Color.buoyOverlayStroke,
                                lineWidth: isChosen(swatch) ? 2 : 1
                            )
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .accessibilityLabel("\(swatch.familyName) \(BuoyWording.colorLowercased)")
                .accessibilityAddTraits(isChosen(swatch) ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// A preset reads as chosen only on an exact match, so nudging either
    /// slider afterwards quietly releases it rather than leaving a ring on a
    /// swatch that is no longer what you have.
    private func isChosen(_ swatch: HSBColor) -> Bool {
        selection == swatch
    }

    private func strip(
        gradient: LinearGradient,
        value: Double,
        isEnabled: Bool,
        label: String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(gradient)
                .overlay(Capsule().strokeBorder(Color.buoyOverlayStroke, lineWidth: 1))
                .overlay(alignment: .leading) {
                    if selection != nil {
                        knob
                            .offset(x: (proxy.size.width - Self.stripHeight) * value)
                    }
                }
                .contentShape(Capsule())
                // Both, deliberately: a `DragGesture` with `minimumDistance: 0`
                // does not reliably deliver `onChanged` for a press that never
                // moves, and clicking straight at a colour is the first thing
                // anyone tries.
                .onTapGesture(coordinateSpace: .local) { point in
                    onChange(fraction(for: point.x, width: proxy.size.width))
                }
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        onChange(fraction(for: drag.location.x, width: proxy.size.width))
                    }
                )
        }
        .frame(height: Self.stripHeight)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            let step = (direction == .increment ? 1.0 : -1.0) / 20
            onChange(min(1, max(0, value + step)))
        }
    }

    private var knob: some View {
        Circle()
            .fill(selection?.color ?? .clear)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .frame(width: Self.stripHeight, height: Self.stripHeight)
            .allowsHitTesting(false)
    }

    private func fraction(for x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1))
    }
}

/// One colour on the Appearance page: what it is, how to change it, and the
/// way back to the default.
struct ColorPickerColumn: View {
    let title: String
    @Binding var selection: HSBColor?
    /// Shown only for the window tint. An accent has no "how much" — it either
    /// is the accent or it is not.
    var intensity: Binding<Double>?
    /// What the swatch says when nothing is chosen.
    let defaultName: String
    let brightness: Double

    @State private var colorPanelObserver: ColorPanelObserver?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selection?.color ?? Color(nsColor: .controlAccentColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.buoyOverlayStroke, lineWidth: 1)
                    )
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(BuoyFont.control)
                    Text(selection?.familyName ?? defaultName)
                        .font(BuoyFont.secondary)
                        .foregroundStyle(.secondary)
                }
            }

            ColorStripPicker(selection: $selection, brightness: brightness)

            if let intensity {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Intensity")
                        .font(BuoyFont.secondary)
                        .foregroundStyle(.secondary)
                    Slider(value: intensity, in: 0...1)
                        .controlSize(.small)
                        .disabled(selection == nil)
                        .accessibilityLabel("\(title) intensity")
                        .accessibilityValue("\(Int(intensity.wrappedValue * 100)) percent")
                }
            }

            HStack(spacing: 8) {
                Button("Reset") { selection = nil }
                    .disabled(selection == nil)
                Button("Exact…") { openColorPanel() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// The strips cannot express "exactly this colour", and some people arrive
    /// with a hex value in hand. Rather than put a hex field on the page, hand
    /// them the system picker they already know.
    private func openColorPanel() {
        let panel = NSColorPanel.shared
        let observer = ColorPanelObserver { color in
            guard let converted = color.usingColorSpace(.deviceRGB) else { return }
            selection = HSBColor(
                hue: Double(converted.hueComponent),
                saturation: Double(converted.saturationComponent),
                brightness: Double(converted.brightnessComponent)
            )
        }
        colorPanelObserver = observer
        panel.setTarget(observer)
        panel.setAction(#selector(ColorPanelObserver.colorChanged(_:)))
        panel.color = (selection ?? HSBColor(hue: 0.58, saturation: 0.6, brightness: brightness)).nsColor
        panel.isContinuous = true
        panel.makeKeyAndOrderFront(nil)
    }
}

/// Target for `NSColorPanel`, which is an old-style target/action API and has
/// nowhere to put a closure.
private final class ColorPanelObserver: NSObject {
    private let onChange: (NSColor) -> Void

    init(onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        onChange(sender.color)
    }
}
