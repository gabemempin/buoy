import SwiftUI
import AppKit

/// Hue-and-saturation wheel: angle is the hue, distance from the centre is the
/// saturation, and the handle is wherever the current colour sits.
///
/// Brightness is fixed by the caller rather than exposed. A third axis would
/// make the control a colour *editor*, and the thing being chosen here is a
/// tint — "which colour", not "which exact shade".
struct ColorWheel: View {
    @Binding var selection: HSBColor?
    /// Used when the user first drags on a wheel that has no colour yet.
    let brightness: Double
    var diameter: CGFloat = 132

    private var radius: CGFloat { diameter / 2 }

    private static let hueStops: [Color] = (0...12).map { step in
        Color(hue: Double(step) / 12, saturation: 1, brightness: 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: Self.hueStops, center: .center))
                .overlay {
                    // Saturation falls off toward the centre, so the middle of
                    // the wheel is white and the rim is fully saturated.
                    Circle().fill(
                        RadialGradient(
                            colors: [.white, .white.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
                .overlay(Circle().strokeBorder(Color.buoyOverlayStroke, lineWidth: 1))

            handle
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        // Both, deliberately. A `DragGesture` with `minimumDistance: 0` does
        // not reliably deliver `onChanged` for a press-and-release that never
        // moves, so on its own the wheel only responds to dragging — and
        // clicking straight at a colour is the first thing anyone tries.
        .onTapGesture(coordinateSpace: .local) { location in select(at: location) }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in select(at: value.location) }
        )
        .accessibilityElement()
        .accessibilityLabel("Colour wheel")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            let current = selection ?? HSBColor(hue: 0, saturation: 0.6, brightness: brightness)
            // A 15° step, so a full turn is 24 presses rather than 360.
            let delta = (direction == .increment ? 1.0 : -1.0) / 24
            var hue = current.hue + delta
            if hue < 0 { hue += 1 }
            if hue > 1 { hue -= 1 }
            selection = HSBColor(hue: hue, saturation: current.saturation, brightness: current.brightness)
        }
    }

    private var accessibilityValue: String {
        guard let selection else { return "None" }
        return "\(selection.familyName), hue \(Int(selection.hue * 360)) degrees, saturation \(Int(selection.saturation * 100)) percent"
    }

    @ViewBuilder
    private var handle: some View {
        if let selection {
            let angle = selection.hue * 2 * .pi
            let distance = selection.saturation * radius
            Circle()
                .fill(selection.color)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .frame(width: 16, height: 16)
                .offset(
                    x: CoreGraphics.cos(angle) * distance,
                    y: CoreGraphics.sin(angle) * distance
                )
                .allowsHitTesting(false)
        }
    }

    /// Converts a point in the wheel to a hue and saturation.
    ///
    /// Not animated: the handle has to track the pointer exactly, and an
    /// implicit animation here makes it lag behind the finger on every drag.
    private func select(at point: CGPoint) {
        let dx = point.x - radius
        let dy = point.y - radius
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }

        let distance = min(sqrt(dx * dx + dy * dy), radius)
        let existingBrightness = selection?.brightness ?? brightness
        selection = HSBColor(
            hue: Double(angle / (2 * .pi)),
            saturation: radius > 0 ? Double(distance / radius) : 0,
            brightness: existingBrightness
        )
    }
}

/// A full colour row on the Appearance page: the wheel, what it currently is,
/// optionally how strongly it applies, and a way back to the default.
struct ColorWheelRow: View {
    let title: String
    @Binding var selection: HSBColor?
    /// Shown only for the window tint. An accent has no "how much" — it either
    /// is the accent or it is not.
    var intensity: Binding<Double>?
    /// What the swatch says when nothing is chosen ("Default", "System accent").
    let defaultName: String
    let brightness: Double

    @State private var colorPanelDelegate: ColorPanelObserver?

    var body: some View {
        LabeledContent(title) {
            HStack(alignment: .top, spacing: 16) {
                ColorWheel(selection: $selection, brightness: brightness)

                VStack(alignment: .leading, spacing: 10) {
                    swatch

                    if let intensity {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Intensity")
                                .font(BuoyFont.secondary)
                                .foregroundStyle(.secondary)
                            Slider(value: intensity, in: 0...1)
                                .frame(width: 140)
                                .accessibilityLabel("\(title) intensity")
                                .accessibilityValue("\(Int(intensity.wrappedValue * 100)) percent")
                        }
                    }

                    HStack(spacing: 8) {
                        Button("Reset") { selection = nil }
                            .disabled(selection == nil)
                        Button("Exact colour…") { openColorPanel() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(width: 200, alignment: .leading)
            }
            .padding(.vertical, 6)
        }
    }

    private var swatch: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selection?.color ?? Color(nsColor: .controlAccentColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.buoyOverlayStroke, lineWidth: 1)
                )
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text(selection?.familyName ?? defaultName)
                .font(BuoyFont.control)
        }
    }

    /// The wheel cannot express "exactly this colour", and some people arrive
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
        colorPanelDelegate = observer
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
