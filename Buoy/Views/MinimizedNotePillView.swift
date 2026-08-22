import SwiftUI

struct MinimizedNotePillView: View {
    let title: String
    let theme: AppTheme
    var onRestore: () -> Void
    @State private var isRestoreHovering = false

    var body: some View {
        GeometryReader { proxy in
            let laneWidth = PanelLayoutMetrics.minimizedTitleLaneWidth(forPillWidth: proxy.size.width)

            HStack(spacing: PanelLayoutMetrics.minimizedTitleButtonSpacing) {
                MinimizedTitleLane(title: title, theme: theme, availableWidth: laneWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onRestore) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.buoyOnAccent(isProminent: isRestoreHovering))
                        .frame(
                            width: PanelLayoutMetrics.minimizedRestoreButtonSize,
                            height: PanelLayoutMetrics.minimizedRestoreButtonSize
                        )
                        .contentShape(Circle())
                        .buoyAccentCircle(isHovering: isRestoreHovering)
                }
                .buttonStyle(.plain)
                .help("Restore note")
                .accessibilityLabel("Restore note")
                .onHover { isRestoreHovering = $0 }
            }
            .padding(.leading, PanelLayoutMetrics.minimizedPillLeadingPadding)
            .padding(.trailing, PanelLayoutMetrics.minimizedPillTrailingPadding)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(height: PanelLayoutMetrics.minimizedPillHeight)
        .background(WindowDragHandle())
        .buoyGlassCapsule()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Harbor Mode: \(title.isEmpty ? "Untitled" : title)")
    }
}

private struct MinimizedTitleLane: View {
    let title: String
    let theme: AppTheme
    let availableWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MarqueeText(
            text: PanelLayoutMetrics.minimizedDisplayTitle(title),
            font: PanelLayoutMetrics.minimizedTitleFont,
            color: minimizedTitleColor(theme: theme, colorScheme: colorScheme),
            availableWidth: availableWidth
        )
        .allowsHitTesting(false)
    }
}

private func minimizedTitleColor(theme: AppTheme, colorScheme: ColorScheme) -> Color {
    switch theme {
    case .light:
        return .accentColor
    case .dark:
        return .white
    case .system:
        return colorScheme == .dark ? .white : .accentColor
    }
}
