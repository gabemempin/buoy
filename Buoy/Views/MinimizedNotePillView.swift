import SwiftUI

struct MinimizedNotePillView: View {
    let title: String
    let theme: AppTheme
    let timer: HarborTimer
    var onRestore: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let laneWidth = PanelLayoutMetrics.minimizedTitleLaneWidth(forPillWidth: proxy.size.width)

            HStack(spacing: timer.isActive ? 8 : PanelLayoutMetrics.minimizedTitleButtonSpacing) {
                if timer.isActive {
                    Text(timer.displayText)
                        .font(Font(PanelLayoutMetrics.minimizedTitleFont))
                        .monospacedDigit()
                        .foregroundStyle(minimizedTitleColor(theme: theme, colorScheme: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(timer.isFinished ? "Time’s up" : "Time remaining: \(timer.displayText)")
                    HarborPillButton(
                        symbol: timer.isPaused ? "play.fill" : "pause.fill",
                        label: timer.isPaused ? "Continue timer" : "Pause timer",
                        action: timer.togglePause
                    )
                    .disabled(timer.isFinished)
                    HarborPillButton(symbol: "stop.fill", label: "Stop timer", color: .red, action: timer.stop)
                } else {
                    MinimizedTitleLane(title: title, theme: theme, availableWidth: laneWidth)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HarborPillButton(symbol: "chevron.down", label: "Restore note", action: onRestore)
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

private struct HarborPillButton: View {
    let symbol: String
    let label: String
    var color: Color? = nil
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color == nil ? Color.buoyOnAccent(isProminent: isHovering) : .white)
                .frame(width: PanelLayoutMetrics.minimizedRestoreButtonSize, height: PanelLayoutMetrics.minimizedRestoreButtonSize)
                .contentShape(Circle())
                .buoyAccentCircle(color: color, isHovering: isHovering)
        }
        .buttonStyle(HarborTimerButtonStyle())
        .help(label)
        .accessibilityLabel(label)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
    }
}

private struct HarborTimerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.55 : 1)
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
    let resolvedScheme: ColorScheme
    switch theme {
    case .light:
        resolvedScheme = .light
    case .dark:
        resolvedScheme = .dark
    case .system:
        resolvedScheme = colorScheme
    }
    return Color(nsColor: BuoyTheme.current.accentText(isDark: resolvedScheme == .dark))
}
