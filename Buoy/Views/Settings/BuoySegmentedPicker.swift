import SwiftUI

/// The glass segmented control Calendar uses for Day / Week / Month / Year.
///
/// One control for both the window's page picker and the Light/Dark choice, so
/// the two cannot drift apart. `Picker(.segmented)` was used for the latter and
/// rendered as a hard-edged rectangle inside a glass window — this is the same
/// idea with the app's own corner radius and material.
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

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(3)
        .buoyGlassCapsule()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = selection == option.value
        return Button {
            guard !isSelected else { return }
            withAnimation(BuoyMotion.spring(response: 0.3, dampingFraction: 0.85)) {
                selection = option.value
            }
        } label: {
            HStack(spacing: 5) {
                if let symbolName = option.symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(option.title)
                    .font(BuoyFont.control)
                    // Both, or a segment wraps its label the moment the window
                    // is narrow — which is exactly what it did.
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    // Matched, so the pill slides between segments instead of
                    // blinking out of one and into the next.
                    Capsule()
                        .fill(Color.buoySegmentSelection)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
