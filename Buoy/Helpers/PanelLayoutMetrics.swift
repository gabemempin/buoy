import AppKit

enum PanelLayoutMetrics {
    static let windowPadding: CGFloat = 6
    static let stackSpacing: CGFloat = 4
    static let onboardingInset: CGFloat = 2
    static let onboardingCornerRadius: CGFloat = 15
    static let overlayHorizontalInset: CGFloat = 8
    static let allNotesTopInset: CGFloat = 43
    static let allNotesBottomInset: CGFloat = 43
    static let footerOverlayBottomInset: CGFloat = 43

    static let headerMinimumHeight: CGFloat = 70
    static let toolbarMinimumHeight: CGFloat = 36
    static let footerMinimumHeight: CGFloat = 68
    static let editorMinimumHeight: CGFloat = 160

    private static let headerControlsMinimumWidth: CGFloat = 12 + 60 + 74 + 8
    private static let titleRowMinimumWidth: CGFloat = 24 + 180
    private static let toolbarMinimumWidth: CGFloat = 16 + (6 * 30) + 5
    private static let footerMinimumWidth: CGFloat = 16 + 62 + 104
    private static let settingsOverlayMinimumWidth: CGFloat = 260 + 8 + 24

    static let minimumContentWidth: CGFloat = max(
        headerControlsMinimumWidth,
        titleRowMinimumWidth,
        toolbarMinimumWidth,
        footerMinimumWidth,
        settingsOverlayMinimumWidth
    )

    static let minimumWindowWidth: CGFloat = minimumContentWidth

    static let minimumWindowHeight: CGFloat =
        (windowPadding * 2)
        + headerMinimumHeight
        + toolbarMinimumHeight
        + editorMinimumHeight
        + footerMinimumHeight
        + (stackSpacing * 3)

    static let maximumAutoHeight: CGFloat = 700

    // Minimum window heights when overlay panels are open
    static let settingsOverrideHeight: CGFloat = 470
    static let shortcutsOverrideHeight: CGFloat = 468
    static let onboardingOverrideHeight: CGFloat = 450

    // Minimized pill layout
    static let minimizedPillHeight: CGFloat = 56
    static let minimizedWindowHeight: CGFloat = minimizedPillHeight + (windowPadding * 2)
    static let minimizedWindowMinimumWidth: CGFloat = 240
    static let minimizedWindowMaximumWidth: CGFloat = 520
    static let minimizedPillLeadingPadding: CGFloat = 22
    static let minimizedPillTrailingPadding: CGFloat = 12
    static let minimizedTitleButtonSpacing: CGFloat = 14
    static let minimizedRestoreButtonSize: CGFloat = 28
    static let minimizedMarqueeGap: CGFloat = 32
    static let minimizedTitleEdgeFadeWidth: CGFloat = 24
    static let minimizedTransitionDuration: TimeInterval = 0.22
    static let minimizedFrameAnimationDuration: TimeInterval = 0.26
    static let minimizedMarqueePause: TimeInterval = 1.2
    static let minimizedMarqueePointsPerSecond: CGFloat = 34
    static let minimizedTitleFont = NSFont.systemFont(ofSize: 19, weight: .semibold, width: .expanded)

    static func minimizedDisplayTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    static func minimizedTitleWidth(forTitle title: String) -> CGFloat {
        let measured = (minimizedDisplayTitle(title) as NSString).size(
            withAttributes: [.font: minimizedTitleFont]
        )
        return ceil(measured.width)
    }

    static func minimizedTitleLaneWidth(forWindowWidth windowWidth: CGFloat) -> CGFloat {
        let available = windowWidth
            - (windowPadding * 2)
            - minimizedPillLeadingPadding
            - minimizedPillTrailingPadding
            - minimizedTitleButtonSpacing
            - minimizedRestoreButtonSize
        return max(0, available)
    }

    static func minimizedWindowWidth(forTitle title: String) -> CGFloat {
        let unclamped = (windowPadding * 2)
            + minimizedPillLeadingPadding
            + minimizedTitleWidth(forTitle: title)
            + minimizedTitleButtonSpacing
            + minimizedRestoreButtonSize
            + minimizedPillTrailingPadding
        return min(
            max(minimizedWindowMinimumWidth, unclamped),
            minimizedWindowMaximumWidth
        )
    }
}
