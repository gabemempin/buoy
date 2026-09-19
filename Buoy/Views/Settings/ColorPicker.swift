import SwiftUI
import AppKit

/// An HSL colour wheel: hue around, saturation out from the centre.
///
/// Lightness is fixed by the caller rather than exposed. A third axis would
/// make this a colour *editor*, and what is being chosen here is a hue — at
/// L = 0.5 the rim is the fully saturated colours and the centre is white,
/// which is the wheel people recognise.
struct ColorWheel: View {
    @Binding var selection: HSLColor?
    let lightness: Double
    var diameter: CGFloat = 116

    private var radius: CGFloat { diameter / 2 }

    private var hueStops: [Color] {
        (0...24).map { step in
            HSLColor(hue: Double(step) / 24, saturation: 1, lightness: lightness).color
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: hueStops, center: .center))
                .overlay {
                    // Saturation falls off toward the middle. At L = 0.5 a
                    // fully desaturated colour is mid grey, not white, so the
                    // centre fades to that rather than to white — otherwise the
                    // wheel lies about what the centre will give you.
                    Circle().fill(
                        RadialGradient(
                            colors: [
                                HSLColor(hue: 0, saturation: 0, lightness: lightness).color,
                                HSLColor(hue: 0, saturation: 0, lightness: lightness).color.opacity(0)
                            ],
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
        // Both, deliberately: a `DragGesture` with `minimumDistance: 0` does
        // not reliably deliver `onChanged` for a press that never moves, and
        // clicking straight at a colour is the first thing anyone tries.
        .onTapGesture(coordinateSpace: .local) { select(at: $0) }
        .gesture(DragGesture(minimumDistance: 0).onChanged { select(at: $0.location) })
        .accessibilityElement()
        .accessibilityLabel("\(BuoyWording.color) wheel")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            let current = selection ?? HSLColor(hue: 0, saturation: 0.7, lightness: lightness)
            // A 15° step, so a full turn is 24 presses rather than 360.
            var hue = current.hue + (direction == .increment ? 1.0 : -1.0) / 24
            if hue < 0 { hue += 1 }
            if hue > 1 { hue -= 1 }
            selection = HSLColor(hue: hue, saturation: current.saturation, lightness: current.lightness)
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
                .frame(width: 15, height: 15)
                .offset(
                    x: CoreGraphics.cos(angle) * distance,
                    y: CoreGraphics.sin(angle) * distance
                )
                .allowsHitTesting(false)
        }
    }

    /// Not animated: the handle has to track the pointer exactly, and an
    /// implicit animation here makes it lag behind the finger on every drag.
    private func select(at point: CGPoint) {
        let dx = point.x - radius
        let dy = point.y - radius
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        let distance = min(sqrt(dx * dx + dy * dy), radius)
        selection = HSLColor(
            hue: Double(angle / (2 * .pi)),
            saturation: radius > 0 ? Double(distance / radius) : 0,
            lightness: selection?.lightness ?? lightness
        )
    }
}

/// One colour on the Appearance page: what it is, the wheel, and the way back
/// to the default.
struct ColorPickerColumn: View {
    let title: String
    @Binding var selection: HSLColor?
    /// Shown only for the window tint. An accent has no "how much" — it either
    /// is the accent or it is not.
    var opacity: Binding<Double>?
    /// What the swatch says when nothing is chosen.
    let defaultName: String
    let lightness: Double

    @State private var colorPanelObserver: ColorPanelObserver?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            ColorWheel(selection: $selection, lightness: lightness)
                .frame(maxWidth: .infinity, alignment: .center)

            // Reserved on both columns whether or not this one has a slider, so
            // the two sit level and the buttons line up across the row.
            opacityRow
                .frame(height: 30)

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

    private var header: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selection?.color ?? Color(nsColor: .controlAccentColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.buoyOverlayStroke, lineWidth: 1)
                )
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(BuoyFont.control)
                Text(selection?.familyName ?? defaultName)
                    .font(BuoyFont.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var opacityRow: some View {
        if let opacity {
            VStack(alignment: .leading, spacing: 1) {
                Text("Opacity")
                    .font(BuoyFont.secondary)
                    .foregroundStyle(.secondary)
                Slider(value: opacity, in: 0...1)
                    .controlSize(.small)
                    .disabled(selection == nil)
                    .accessibilityLabel("\(title) opacity")
                    .accessibilityValue("\(Int(opacity.wrappedValue * 100)) percent")
            }
        } else {
            Color.clear
        }
    }

    /// The wheel cannot express "exactly this colour", and some people arrive
    /// with a hex value in hand. Rather than put a hex field on the page, hand
    /// them the system picker they already know.
    private func openColorPanel() {
        let panel = NSColorPanel.shared
        let observer = ColorPanelObserver { color in
            guard let rgb = color.usingColorSpace(.sRGB) else { return }
            selection = HSLColor(
                red: Double(rgb.redComponent),
                green: Double(rgb.greenComponent),
                blue: Double(rgb.blueComponent)
            )
        }
        colorPanelObserver = observer
        panel.setTarget(observer)
        panel.setAction(#selector(ColorPanelObserver.colorChanged(_:)))
        panel.color = (selection ?? HSLColor(hue: 0.58, saturation: 0.7, lightness: lightness)).nsColor
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
