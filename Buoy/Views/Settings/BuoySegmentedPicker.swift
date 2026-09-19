import SwiftUI

/// The segmented control Calendar uses for Day / Week / Month / Year.
///
/// Measured off the real thing rather than guessed at. At rest it is a flat
/// track with a solid pill on the selection — no shadow, no glass rim, no
/// lift. The material only appears while the control is being *used*: pressing
/// turns the pill into a clear glass lens with a bright refractive rim that
/// follows the pointer continuously between segments, and lets go onto
/// whichever one it ends over.
///
/// Segments take their natural width, as Calendar's do, so "General" does not
/// get the same lane as "Appearance". That rules out arithmetic on an index,
/// so each segment reports its own frame and the indicator is placed from
/// those — and interpolated between them while a drag is in flight.
struct BuoySegmentedPicker<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        /// Optional; the theme picker is text only.
        var symbolName: String?

        var id: Value { value }
    }

    @Binding var selection: Value
    let options: [Option]
    var accessibilityLabel: String

    private static var space: String { "BuoySegmentedPicker" }

    /// Each segment's frame in the control's own space, keyed by index.
    @State private var frames: [Int: CGRect] = [:]
    /// Pointer position while dragging, in the control's space. `nil` at rest,
    /// which is what puts the indicator back on the selected segment.
    @State private var dragX: CGFloat?

    private var selectedIndex: Int {
        options.firstIndex { $0.value == selection } ?? 0
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                segment(option, index: index, isSelected: index == selectedIndex)
            }
        }
        .background(alignment: .topLeading) { indicator }
        .padding(3)
        .background(Capsule().fill(Color.buoySegmentTrack))
        .coordinateSpace(name: Self.space)
        .gesture(dragGesture)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Segments

    private func segment(_ option: Option, index: Int, isSelected: Bool) -> some View {
        HStack(spacing: 5) {
            if let symbolName = option.symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .medium))
            }
            Text(option.title)
                .font(BuoyFont.control)
                // Both, or a segment wraps its label the moment the window is
                // narrow — which is exactly what it did.
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(frameReader(index: index))
        .onTapGesture { select(option.value) }
        // Without this the icon and the label reach VoiceOver as two separate
        // buttons for one segment.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // A tap gesture is not an action VoiceOver can perform, so pressing a
        // segment has to be spelled out separately from the gesture that
        // handles the pointer.
        .accessibilityAction { select(option.value) }
    }

    private func frameReader(index: Int) -> some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(Self.space))
            Color.clear
                .onAppear { frames[index] = frame }
                .onChange(of: frame) { _, newValue in frames[index] = newValue }
        }
    }

    // MARK: Indicator

    @ViewBuilder
    private var indicator: some View {
        if let frame = indicatorFrame {
            Group {
                if dragX != nil { lens } else { Capsule().fill(Color.buoySegmentSelection) }
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX - 3, y: frame.minY - 3)
            .allowsHitTesting(false)
        }
    }

    /// The selected segment's frame, or — mid-drag — a blend of the two the
    /// pointer sits between, so the lens stretches across the gap rather than
    /// jumping from one to the next.
    private var indicatorFrame: CGRect? {
        guard let resting = frames[selectedIndex] else { return nil }
        guard let dragX else { return resting }

        let ordered = frames.sorted { $0.key < $1.key }.map(\.value)
        guard ordered.count == options.count else { return resting }

        guard let after = ordered.firstIndex(where: { dragX < $0.midX }) else {
            return ordered[ordered.count - 1]
        }
        guard after > 0 else { return ordered[0] }

        let low = ordered[after - 1]
        let high = ordered[after]
        let span = high.midX - low.midX
        let t = span > 0 ? min(max((dragX - low.midX) / span, 0), 1) : 0
        return CGRect(
            x: low.minX + (high.minX - low.minX) * t,
            y: low.minY,
            width: low.width + (high.width - low.width) * t,
            height: low.height
        )
    }

    /// The clear glass lens. Its rim is what reads while it moves — the fill
    /// stays transparent so the label underneath is still legible through it.
    @ViewBuilder
    private var lens: some View {
        if #available(macOS 26, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
        }
    }

    // MARK: Interaction

    private func select(_ value: Value) {
        guard value != selection else { return }
        withAnimation(BuoyMotion.spring(response: 0.3, dampingFraction: 0.85)) {
            selection = value
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragX == nil {
                    withAnimation(BuoyMotion.easeOut(0.12)) { dragX = value.location.x }
                } else {
                    dragX = value.location.x
                }
                // The selection follows the lens, so the page changes under it
                // as it passes rather than only once it is let go.
                if let nearest = nearestIndex(to: value.location.x),
                   options[nearest].value != selection {
                    selection = options[nearest].value
                }
            }
            .onEnded { _ in
                withAnimation(BuoyMotion.spring(response: 0.32, dampingFraction: 0.8)) {
                    dragX = nil
                }
            }
    }

    private func nearestIndex(to x: CGFloat) -> Int? {
        frames
            .min { abs($0.value.midX - x) < abs($1.value.midX - x) }?
            .key
    }
}
