import CoreGraphics

enum PanelLayoutMetrics {
    static let windowPadding: CGFloat = 6
    static let stackSpacing: CGFloat = 4
    static let onboardingInset: CGFloat = 2
    static let onboardingCornerRadius: CGFloat = 15

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
}
