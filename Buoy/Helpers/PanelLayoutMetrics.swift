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
    static let allNotesNoteRowHeight: CGFloat = 34
    static let allNotesFolderRowHeight: CGFloat = 32
    static let allNotesDividerRowHeight: CGFloat = 9
    /// A labelled section header ("Pinned", "Folders", "All Notes"). A bare
    /// rule told the user the list was grouped but never why.
    static let allNotesHeaderRowHeight: CGFloat = 26
    /// Left inset on the list itself. AppKit draws the drop indicator from the
    /// row's leading edge and its round end cap overhangs to the *left* of
    /// that, so without this the circle is clipped against the panel edge.
    /// Rows subtract the same amount from their own leading padding, so this
    /// buys the indicator room without moving any text.
    static let allNotesListLeadingInset: CGFloat = 5
    /// Extra leading inset for a note shown inside a folder.
    static let allNotesChildIndent: CGFloat = 18
    static let footerOverlayBottomInset: CGFloat = 43

    // Section minimum heights now live on `ChromeMetrics`, because they are
    // the thing compact chrome shrinks. Everything below reads them from a
    // density rather than holding its own copy.

    // Width minimums live on `ChromeMetrics` alongside the heights, because
    // compact controls take less room across as well as down.

    static func minimumContentWidth(for metrics: ChromeMetrics) -> CGFloat {
        max(
            metrics.headerMinimumWidth,
            metrics.titleRowMinimumWidth,
            metrics.toolbarMinimumWidth,
            metrics.footerMinimumWidth,
            metrics.comfortableContentWidth
        )
    }

    /// Minimum size of the glass surface itself — what the SwiftUI content is
    /// framed against, inside the shadow margin.
    static func minimumGlassWidth(for metrics: ChromeMetrics) -> CGFloat {
        minimumContentWidth(for: metrics)
    }

    static func minimumWindowWidth(for metrics: ChromeMetrics) -> CGFloat {
        minimumGlassWidth(for: metrics) + (glassEdgeInset * 2)
    }

    /// The absolute floor the panel can be dragged to, on the same reasoning
    /// as `minimumWindowHeight`: dragging below the regular minimum is what
    /// asks for compact chrome, so the floor has to be the compact one.
    static let minimumWindowWidth: CGFloat = minimumWindowWidth(for: .compact)

    /// The narrowest the panel can be while still drawing regular chrome, and
    /// the width it launches at.
    static let regularChromeWindowWidth: CGFloat = minimumWindowWidth(for: .regular)

    static let compactChromeEnterWidth: CGFloat = regularChromeWindowWidth


    static func minimumGlassHeight(for metrics: ChromeMetrics) -> CGFloat {
        (windowPadding * 2)
        + metrics.headerMinimumHeight
        + metrics.toolbarMinimumHeight
        + metrics.editorMinimumHeight
        + metrics.footerMinimumHeight
        + (stackSpacing * 3)
    }

    // Minimum size of the panel *window* — the glass plus its shadow margin on
    // every side. All AppKit frame math works in these terms.

    static func minimumWindowHeight(for metrics: ChromeMetrics) -> CGFloat {
        minimumGlassHeight(for: metrics) + (glassEdgeInset * 2)
    }

    /// The absolute floor the panel can be dragged to: the compact chrome's
    /// minimum. AppKit is floored here at all times rather than at the regular
    /// minimum, because dragging *below* the regular minimum is precisely what
    /// asks for compact chrome — a floor at 382 would make it unreachable.
    static let minimumWindowHeight: CGFloat = minimumWindowHeight(for: .compact)

    /// The shortest the panel can be while still drawing regular chrome, and
    /// the height it launches at.
    static let regularChromeWindowHeight: CGFloat = minimumWindowHeight(for: .regular)

    static let compactChromeEnterHeight: CGFloat = regularChromeWindowHeight

    static let maximumAutoHeight: CGFloat = 700 + (glassEdgeInset * 2)

    // Minimum window heights for the two full-panel takeovers. Expressed as
    // glass heights plus the margin so the visible panel keeps its intended
    // size. Settings and Shortcuts used to be here too; they are a separate
    // window now and no longer resize the panel at all.
    static let onboardingOverrideHeight: CGFloat = 450 + (glassEdgeInset * 2)
    /// The What's New splash. Its content scrolls, so a long release never grows
    /// the window past this and a short one just leaves air above the button.
    static let whatsNewOverrideHeight: CGFloat = 560 + (glassEdgeInset * 2)

    // Minimized pill layout
    static let minimizedPillHeight: CGFloat = 56
    static let minimizedWindowHeight: CGFloat = minimizedPillHeight + (glassEdgeInset * 2)
    static let minimizedWindowMinimumWidth: CGFloat = 240
    /// The pill never narrows with the chrome: it is its own layout, sized to
    /// the title, and it keeps the panel's regular width as its ceiling.
    static let minimizedWindowMaximumWidth: CGFloat = regularChromeWindowWidth
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
