import AppKit

enum PanelLayoutMetrics {
    /// macOS 27 unified every window on a single 16pt corner radius
    /// (measured via `-[NSWindow _cornerRadius]` on 27.0). Buoy's panel is
    /// borderless, so it has to draw that radius itself.
    static let windowCornerRadius: CGFloat = 16

    /// Transparent margin between the window's edge and the glass surface.
    ///
    /// The panel carries no AppKit window shadow (`hasShadow = false`) — on a
    /// transparent window that shadow's inner edge is never covered and renders
    /// as a hard ring. `BuoyRegularGlassModifier.shadowRing` draws the shadow
    /// into this margin instead. Must stay >= the ring's radius + y-offset, or
    /// the shadow clips at the window bounds.
    ///
    /// Set to 0 for an edge-to-edge surface with no drop shadow at all.
    static let glassEdgeInset: CGFloat = 12

    /// Inset from the *glass* edge to the content inside it.
    static let windowPadding: CGFloat = 6
    static let stackSpacing: CGFloat = 4
    static let onboardingInset: CGFloat = 2
    /// Concentric with the window, inset by the content padding.
    static let onboardingCornerRadius: CGFloat = windowCornerRadius - windowPadding + 1
    static let overlayHorizontalInset: CGFloat = 8
    static let allNotesTopInset: CGFloat = 43
    static let allNotesBottomInset: CGFloat = 43

    // All Notes list. The outline view sizes each row by kind rather than
    // carrying one global rowHeight, so a folder row and a divider can differ
    // from a note row without the list going out of alignment.
    static let allNotesListMaxHeight: CGFloat = 300
    static let allNotesNoteRowHeight: CGFloat = 30
    static let allNotesFolderRowHeight: CGFloat = 28
    static let allNotesDividerRowHeight: CGFloat = 9
    /// A labelled section header ("Pinned", "Folders", "All Notes"). A bare
    /// rule told the user the list was grouped but never why.
    static let allNotesHeaderRowHeight: CGFloat = 26
    /// Extra leading inset for a note shown inside a folder.
    static let allNotesChildIndent: CGFloat = 18
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

    // Minimum size of the glass surface itself — what the SwiftUI content is
    // framed against, inside the shadow margin.
    static let minimumGlassWidth: CGFloat = minimumContentWidth

    static let minimumGlassHeight: CGFloat =
        (windowPadding * 2)
        + headerMinimumHeight
        + toolbarMinimumHeight
        + editorMinimumHeight
        + footerMinimumHeight
        + (stackSpacing * 3)

    // Minimum size of the panel *window* — the glass plus its shadow margin on
    // every side. All AppKit frame math works in these terms.
    static let minimumWindowWidth: CGFloat = minimumGlassWidth + (glassEdgeInset * 2)

    static let minimumWindowHeight: CGFloat = minimumGlassHeight + (glassEdgeInset * 2)

    static let maximumAutoHeight: CGFloat = 700 + (glassEdgeInset * 2)

    // Minimum window heights when overlay panels are open. Expressed as glass
    // heights plus the margin so the visible panel keeps its intended size.
    //
    // "Auto-name New Notes" only appears in Settings on Macs that support it
    // (see `NoteAutoTitler.isSupported`), so the override height grows by one
    // toggle row only there — a fixed constant would leave dead space on
    // unsupported Macs.
    private static let settingsToggleRowHeight: CGFloat = 28
    static var settingsOverrideHeight: CGFloat {
        let autoTitleRow = NoteAutoTitler.isSupported ? settingsToggleRowHeight : 0
        return 470 + autoTitleRow + (glassEdgeInset * 2)
    }
    static let shortcutsOverrideHeight: CGFloat = 468 + (glassEdgeInset * 2)
    static let onboardingOverrideHeight: CGFloat = 450 + (glassEdgeInset * 2)
    /// The What's New splash. Its content scrolls, so a long release never grows
    /// the window past this and a short one just leaves air above the button.
    static let whatsNewOverrideHeight: CGFloat = 560 + (glassEdgeInset * 2)

    // Minimized pill layout
    static let minimizedPillHeight: CGFloat = 56
    static let minimizedWindowHeight: CGFloat = minimizedPillHeight + (glassEdgeInset * 2)
    static let minimizedWindowMinimumWidth: CGFloat = 240
    static let minimizedWindowMaximumWidth: CGFloat = minimumWindowWidth
    static let minimizedPillLeadingPadding: CGFloat = 22
    static let minimizedPillTrailingPadding: CGFloat = 12
    static let minimizedTitleButtonSpacing: CGFloat = 14
    static let minimizedRestoreButtonSize: CGFloat = 28
    /// Marquee tuning, shared by the Harbor pill and the main header.
    static let marqueeGap: CGFloat = 32
    static let marqueeEdgeFadeWidth: CGFloat = 24
    static let minimizedTransitionDuration: TimeInterval = 0.22
    static let minimizedFrameAnimationDuration: TimeInterval = 0.26
    static let marqueePause: TimeInterval = 1.2
    static let marqueePointsPerSecond: CGFloat = 34

    /// The note title face. The Harbor pill and the main header render the same
    /// title at the same size, so they measure against one font.
    static let minimizedTitleFont = NSFont.systemFont(ofSize: 19, weight: .semibold, width: .expanded)

    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static func minimizedDisplayTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    static func minimizedTitleWidth(forTitle title: String) -> CGFloat {
        textWidth(minimizedDisplayTitle(title), font: minimizedTitleFont)
    }

    static func minimizedTitleLaneWidth(forPillWidth pillWidth: CGFloat) -> CGFloat {
        let available = pillWidth
            - minimizedPillLeadingPadding
            - minimizedPillTrailingPadding
            - minimizedTitleButtonSpacing
            - minimizedRestoreButtonSize
        return max(0, available)
    }

    static func minimizedTitleLaneWidth(forWindowWidth windowWidth: CGFloat) -> CGFloat {
        minimizedTitleLaneWidth(forPillWidth: windowWidth - (glassEdgeInset * 2))
    }

    static func minimizedWindowWidth(forTitle title: String) -> CGFloat {
        let unclamped = (glassEdgeInset * 2)
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
