import SwiftUI
import AppKit

/// Hue ring with a saturation/lightness triangle inside it.
///
/// The shape every drawing app uses, and the reason is that it separates the
/// two questions: the ring is "which colour", the triangle is "how much of it".
/// A plain disc has to fold lightness away somewhere, and it ended up fixed —
/// which meant the only way to get a pale tint was the system picker.
///
/// The triangle's corners are the pure hue, white and black, and every point
/// inside is their barycentric mix. That is exactly what three additive
/// gradients draw, so what is on screen is the colour you get.
struct ColorWheel: View {
    @Binding var selection: HSLColor?
    /// Where an untouched wheel starts, and the lightness a fresh pick on the
    /// ring lands at.
    let defaultLightness: Double
    /// Clamps the lightness a pick can reach. The accent has to stay legible
    /// against the panel whatever the user aims at, so its range stops short
    /// of both white and black.
    var lightnessRange: ClosedRange<Double> = 0...1
    var diameter: CGFloat = 112

    private var radius: CGFloat { diameter / 2 }
    private var ringThickness: CGFloat { 13 }
    private var innerRadius: CGFloat { radius - ringThickness - 3 }

    /// The colour the wheel is currently showing, which is the selection or the
    /// neutral it would start from.
    private var current: HSLColor {
        selection ?? HSLColor(hue: 0.58, saturation: 0, lightness: defaultLightness)
    }

    var body: some View {
        ZStack {
            hueRing
            triangle
            triangleHandle
            ringHandle
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        // Both, deliberately: a `DragGesture` with `minimumDistance: 0` does
        // not reliably deliver `onChanged` for a press that never moves, and
        // clicking straight at a colour is the first thing anyone tries.
        .onTapGesture(coordinateSpace: .local) { handle(point: $0, isStart: true) }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { handle(point: $0.location, isStart: $0.translation == .zero) }
                .onEnded { _ in activeTarget = nil }
        )
        .accessibilityElement()
        .accessibilityLabel("\(BuoyWording.color) wheel")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            // A 15° step, so a full turn is 24 presses rather than 360.
            var hue = current.hue + (direction == .increment ? 1.0 : -1.0) / 24
            if hue < 0 { hue += 1 }
            if hue > 1 { hue -= 1 }
            selection = HSLColor(hue: hue, saturation: max(current.saturation, 0.6), lightness: current.lightness)
        }
    }

    /// Which part of the control the gesture grabbed. Latched at touch-down so
    /// a drag that starts on the ring stays on the ring even when the pointer
    /// wanders across the triangle.
    @State private var activeTarget: Target?

    private enum Target { case ring, triangle }

    private var accessibilityValue: String {
        guard let selection else { return "None" }
        return "\(selection.familyName), hue \(Int(selection.hue * 360)) degrees, "
            + "saturation \(Int(selection.saturation * 100)) percent, "
            + "lightness \(Int(selection.lightness * 100)) percent"
    }

    // MARK: Ring

    private var hueRing: some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: (0...24).map { HSLColor(hue: Double($0) / 24, saturation: 1, lightness: 0.5).color },
                    center: .center
                ),
                lineWidth: ringThickness
            )
            .overlay(Circle().strokeBorder(Color.buoyOverlayStroke, lineWidth: 0.5))
            .overlay(
                Circle()
                    .strokeBorder(Color.buoyOverlayStroke, lineWidth: 0.5)
                    .padding(ringThickness)
            )
    }

    private var ringHandle: some View {
        let angle = current.hue * 2 * .pi
        let distance = radius - ringThickness / 2
        return Circle()
            .fill(HSLColor(hue: current.hue, saturation: 1, lightness: 0.5).color)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            .frame(width: ringThickness + 4, height: ringThickness + 4)
            .offset(x: CoreGraphics.cos(angle) * distance, y: CoreGraphics.sin(angle) * distance)
            .allowsHitTesting(false)
    }

    // MARK: Triangle

    /// Vertices in the view's coordinate space: pure hue, white, black.
    private var vertices: (hue: CGPoint, white: CGPoint, black: CGPoint) {
        let centre = CGPoint(x: radius, y: radius)
        func corner(_ turns: Double) -> CGPoint {
            let angle = (current.hue + turns) * 2 * .pi
            return CGPoint(
                x: centre.x + CoreGraphics.cos(angle) * innerRadius,
                y: centre.y + CoreGraphics.sin(angle) * innerRadius
            )
        }
        return (corner(0), corner(1.0 / 3.0), corner(2.0 / 3.0))
    }

    private var trianglePath: Path {
        let v = vertices
        var path = Path()
        path.move(to: v.hue)
        path.addLine(to: v.white)
        path.addLine(to: v.black)
        path.closeSubpath()
        return path
    }

    /// Black base, plus the hue and white corners added on top.
    ///
    /// A linear gradient running from one vertex to the midpoint of the
    /// opposite edge *is* that vertex's barycentric weight, so compositing the
    /// two additively over black gives `a·hue + b·white` exactly — the same
    /// mix the drag reads back out.
    private var triangle: some View {
        let v = vertices
        let hueColor = HSLColor(hue: current.hue, saturation: 1, lightness: 0.5).color
        return ZStack {
            Color.black
            LinearGradient(
                colors: [hueColor, hueColor.opacity(0)],
                startPoint: .init(unit: v.hue, in: diameter),
                endPoint: .init(unit: midpoint(v.white, v.black), in: diameter)
            )
            .blendMode(.plusLighter)
            LinearGradient(
                colors: [.white, .white.opacity(0)],
                startPoint: .init(unit: v.white, in: diameter),
                endPoint: .init(unit: midpoint(v.hue, v.black), in: diameter)
            )
            .blendMode(.plusLighter)
        }
        .compositingGroup()
        .clipShape(trianglePath)
        .overlay(trianglePath.stroke(Color.buoyOverlayStroke, lineWidth: 0.5))
    }

    private var triangleHandle: some View {
        let position = trianglePosition(for: current)
        return Circle()
            .fill(current.color)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .frame(width: 14, height: 14)
            .position(position)
            .opacity(selection == nil ? 0 : 1)
            .allowsHitTesting(false)
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    // MARK: Gestures

    private func handle(point: CGPoint, isStart: Bool) {
        let dx = point.x - radius
        let dy = point.y - radius
        let distance = sqrt(dx * dx + dy * dy)

        if isStart || activeTarget == nil {
            activeTarget = distance > innerRadius ? .ring : .triangle
        }

        switch activeTarget {
        case .ring:
            var angle = atan2(dy, dx)
            if angle < 0 { angle += 2 * .pi }
            let hue = Double(angle / (2 * .pi))
            // Picking a hue on an untouched wheel should give that hue, not a
            // grey, so a first touch brings saturation with it.
            let saturation = selection == nil ? 0.85 : current.saturation
            selection = HSLColor(
                hue: hue,
                saturation: saturation,
                lightness: clampLightness(selection == nil ? defaultLightness : current.lightness)
            )
        case .triangle, .none:
            selection = colorInTriangle(at: point)
        }
    }

    /// Barycentric weights of `point`, clamped into the triangle, turned back
    /// into a colour.
    private func colorInTriangle(at point: CGPoint) -> HSLColor {
        let v = vertices
        let denominator = (v.white.y - v.black.y) * (v.hue.x - v.black.x)
            + (v.black.x - v.white.x) * (v.hue.y - v.black.y)
        guard abs(denominator) > .ulpOfOne else { return current }

        var a = ((v.white.y - v.black.y) * (point.x - v.black.x)
            + (v.black.x - v.white.x) * (point.y - v.black.y)) / denominator
        var b = ((v.black.y - v.hue.y) * (point.x - v.black.x)
            + (v.hue.x - v.black.x) * (point.y - v.black.y)) / denominator
        a = max(0, a)
        b = max(0, b)
        let total = a + b
        if total > 1 {
            a /= total
            b /= total
        }

        let hueRGB = HSLColor(hue: current.hue, saturation: 1, lightness: 0.5).rgb
        let mixed = HSLColor(
            red: a * hueRGB.red + b,
            green: a * hueRGB.green + b,
            blue: a * hueRGB.blue + b
        )
        return HSLColor(
            hue: current.hue,
            saturation: mixed.saturation,
            lightness: clampLightness(mixed.lightness)
        )
    }

    /// Where a colour's mix sits inside the triangle.
    private func trianglePosition(for color: HSLColor) -> CGPoint {
        let v = vertices
        let hueRGB = HSLColor(hue: color.hue, saturation: 1, lightness: 0.5).rgb
        let rgb = color.rgb
        // Invert `rgb = a·hue + b·white`: the white term is the smallest
        // channel, and the hue term is what is left over on the widest one.
        let b = min(rgb.red, min(rgb.green, rgb.blue))
        let spread = max(hueRGB.red, max(hueRGB.green, hueRGB.blue))
            - min(hueRGB.red, min(hueRGB.green, hueRGB.blue))
        let range = max(rgb.red, max(rgb.green, rgb.blue)) - b
        let a = spread > .ulpOfOne ? range / spread : 0
        let c = max(0, 1 - a - b)
        return CGPoint(
            x: a * v.hue.x + b * v.white.x + c * v.black.x,
            y: a * v.hue.y + b * v.white.y + c * v.black.y
        )
    }

    private func clampLightness(_ value: Double) -> Double {
        min(max(value, lightnessRange.lowerBound), lightnessRange.upperBound)
    }
}

private extension UnitPoint {
    /// A view-space point as a unit point inside a square of `size`.
    init(unit point: CGPoint, in size: CGFloat) {
        self.init(x: size > 0 ? point.x / size : 0, y: size > 0 ? point.y / size : 0)
    }
}

/// One colour on the Appearance page: what it is, the wheel, and the way back
/// to the default.
///
/// Opacity is not in here. It belongs to the window tint alone, and putting it
/// inside that column left the accent column with a reserved gap under its
/// wheel and the two Resets at different heights. It is a form row of its own
/// under the pair instead, which is where a labelled slider belongs anyway.
struct ColorPickerColumn: View {
    let title: String
    @Binding var selection: HSLColor?
    /// What the subtitle says when nothing is chosen.
    let defaultName: String
    let defaultLightness: Double
    var lightnessRange: ClosedRange<Double> = 0...1

    var body: some View {
        VStack(spacing: 9) {
            VStack(spacing: 1) {
                Text(title)
                    .font(BuoyFont.control)
                Text(selection?.familyName ?? defaultName)
                    .font(BuoyFont.secondary)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            ColorWheel(
                selection: $selection,
                defaultLightness: defaultLightness,
                lightnessRange: lightnessRange
            )

            SettingsCapsuleButton("Reset", isEnabled: selection != nil) {
                selection = nil
            }
            .accessibilityLabel("Reset \(title)")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A small pill button that reads on glass.
///
/// `.bordered` renders its background almost invisibly against the Settings
/// window's material, which left every button in here looking like bare blue
/// text. This is the same fill the app's other overlay controls use.
struct SettingsCapsuleButton: View {
    let title: String
    var isEnabled: Bool = true
    var isDestructive: Bool = false
    var width: CGFloat?
    let action: () -> Void

    @State private var isHovering = false

    init(
        _ title: String,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        width: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.width = width
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BuoyFont.secondaryEmphasized)
                .foregroundStyle(isDestructive ? Color.red : Color.primary)
                .lineLimit(1)
                .frame(width: width)
                .padding(.horizontal, width == nil ? 14 : 0)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        Color.buoyControlFill.opacity(isHovering && isEnabled ? 1.6 : 1)
                    )
                )
                .overlay(Capsule().strokeBorder(Color.buoyOverlayStroke, lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
    }
}
