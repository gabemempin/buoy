import SwiftUI

struct MinimizedNotePillView: View {
    let title: String
    let theme: AppTheme
    var onRestore: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let laneWidth = PanelLayoutMetrics.minimizedTitleLaneWidth(forWindowWidth: proxy.size.width)

            HStack(spacing: PanelLayoutMetrics.minimizedTitleButtonSpacing) {
                MinimizedTitleLane(title: title, theme: theme, availableWidth: laneWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onRestore) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(
                            width: PanelLayoutMetrics.minimizedRestoreButtonSize,
                            height: PanelLayoutMetrics.minimizedRestoreButtonSize
                        )
                        .contentShape(Circle())
                        .buoyAccentCircle()
                }
                .buttonStyle(.plain)
                .help("Restore note")
            }
            .padding(.leading, PanelLayoutMetrics.minimizedPillLeadingPadding)
            .padding(.trailing, PanelLayoutMetrics.minimizedPillTrailingPadding)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(height: PanelLayoutMetrics.minimizedPillHeight)
        .background(WindowDragHandle())
        .buoyGlassCapsule()
    }
}

private struct MinimizedTitleLane: View {
    let title: String
    let theme: AppTheme
    let availableWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var measuredTitleWidth: CGFloat {
        PanelLayoutMetrics.minimizedTitleWidth(forTitle: title)
    }

    var body: some View {
        Group {
            if measuredTitleWidth > availableWidth {
                MarqueeTitleView(
                    title: title,
                    theme: theme,
                    textWidth: measuredTitleWidth,
                    availableWidth: availableWidth
                )
            } else {
                titleText
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: availableWidth, alignment: .leading)
        .allowsHitTesting(false)
    }

    private var titleText: some View {
        Text(PanelLayoutMetrics.minimizedDisplayTitle(title))
            .font(Font(PanelLayoutMetrics.minimizedTitleFont))
            .foregroundStyle(titleColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var titleColor: Color {
        minimizedTitleColor(theme: theme, colorScheme: colorScheme)
    }
}

private struct MarqueeTitleView: View {
    let title: String
    let theme: AppTheme
    let textWidth: CGFloat
    let availableWidth: CGFloat

    @State private var cycleAnchor = Date()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            HStack(spacing: PanelLayoutMetrics.minimizedMarqueeGap) {
                titleText
                titleText
            }
            .offset(x: marqueeOffset(at: context.date))
        }
        .frame(width: availableWidth, alignment: .leading)
        .clipped()
        .mask(EdgeFadeMaskView(width: availableWidth))
        .onAppear { cycleAnchor = Date() }
        .onChange(of: title) { _, _ in
            cycleAnchor = Date()
        }
    }

    private var titleText: some View {
        Text(PanelLayoutMetrics.minimizedDisplayTitle(title))
            .font(Font(PanelLayoutMetrics.minimizedTitleFont))
            .foregroundStyle(titleColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var titleColor: Color {
        minimizedTitleColor(theme: theme, colorScheme: colorScheme)
    }

    private func marqueeOffset(at date: Date) -> CGFloat {
        let travel = textWidth + PanelLayoutMetrics.minimizedMarqueeGap
        guard travel > 0 else { return 0 }

        let speed = Double(PanelLayoutMetrics.minimizedMarqueePointsPerSecond)
        let motionDuration = Double(travel) / speed
        let cycleDuration = PanelLayoutMetrics.minimizedMarqueePause + motionDuration
        let elapsed = date.timeIntervalSince(cycleAnchor)
            .truncatingRemainder(dividingBy: cycleDuration)

        guard elapsed > PanelLayoutMetrics.minimizedMarqueePause else { return 0 }
        let movingTime = elapsed - PanelLayoutMetrics.minimizedMarqueePause
        return -CGFloat(movingTime * speed)
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

private struct EdgeFadeMaskView: View {
    let width: CGFloat

    var body: some View {
        let fadeWidth = min(PanelLayoutMetrics.minimizedTitleEdgeFadeWidth, width / 3)
        let fadeFraction = width > 0 ? fadeWidth / width : 0

        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: fadeFraction),
                .init(color: .black, location: 1 - fadeFraction),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
