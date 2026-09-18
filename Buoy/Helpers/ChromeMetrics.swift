import SwiftUI
import AppKit

/// How tightly the panel's chrome is drawn.
///
/// Named `ChromeDensity` rather than anything with "mode" in it because
/// `PanelFullSizeMode.compact` already exists and means something else
/// entirely (the 382-vs-780 height toggle). This is about the *size of the
/// controls*, not the size of the window.
enum ChromeDensity: Equatable {
    case regular
    case compact
}

/// Every size the header, toolbar and footer draw themselves at.
///
/// Chrome shrinks so that a panel the user has dragged short still has a
/// usable editor in it: at the regular sizes the header, toolbar and footer
/// alone claim 174pt, which is most of a short panel. Only chrome scales —
/// note text keeps `AppSettings.fontSize`, because that is a preference about
/// content and shrinking it would be answering a question nobody asked.
struct ChromeMetrics: Equatable {
    var density: ChromeDensity

    static let regular = ChromeMetrics(density: .regular)
    static let compact = ChromeMetrics(density: .compact)

    private var isCompact: Bool { density == .compact }

    private func pick(_ regular: CGFloat, _ compact: CGFloat) -> CGFloat {
        isCompact ? compact : regular
    }

    // MARK: Header

    var headerControlRowHeight: CGFloat { pick(28, 22) }
    var headerTopPadding: CGFloat { pick(6, 3) }
    var headerRowSpacing: CGFloat { pick(6, 3) }
    var headerButtonSize: CGFloat { pick(28, 22) }
    var headerButtonIconSize: CGFloat { pick(12, 10) }
    var headerButtonSpacing: CGFloat { pick(10, 7) }
    var headerButtonTrailingPadding: CGFloat { pick(8, 6) }
    /// Keeps the close button's centre where the old hand-drawn circles sat;
    /// the native buttons are inset 7pt inside their own group.
    var trafficLightsLeadingPadding: CGFloat { pick(15, 11) }
    /// The lights are real AppKit window buttons and have no smaller size to
    /// ask for, so the compact density scales their coordinate system instead.
    /// Held well above a half so they keep their standard proportions and stay
    /// comfortably clickable.
    var trafficLightScale: CGFloat { pick(1, 0.82) }
    /// Rendering scale for the note text.
    ///
    /// Applied as scroll-view magnification, never by changing the editor's
    /// font size. Font size lives in the text storage, so driving it from the
    /// panel's height would rewrite — and save — every note's RTF each time
    /// the window crossed the threshold. A layout gesture must not edit the
    /// document.
    var editorMagnification: CGFloat { pick(1, 0.86) }
    var titleMinHeight: CGFloat { pick(26, 20) }
    var titleHorizontalPadding: CGFloat { pick(12, 10) }
    var titleBottomPadding: CGFloat { pick(4, 2) }
    var titleFontSize: CGFloat { pick(19, 15) }

    /// The face the title is rendered *and measured* in. Overflow detection
    /// has to use the same font the field draws in or the marquee starts
    /// scrolling a title that fits, or sits still under one that does not.
    var titleFont: NSFont {
        NSFont.systemFont(ofSize: titleFontSize, weight: .semibold, width: .expanded)
    }

    // MARK: Toolbar

    var toolbarPillWidth: CGFloat { pick(30, 24) }
    var toolbarPillHeight: CGFloat { pick(28, 22) }
    var toolbarIconSize: CGFloat { pick(12, 10) }
    /// The to-do glyph is drawn smaller than its box at any size, so it takes
    /// its own step up rather than the shared icon size.
    var toolbarTodoIconSize: CGFloat { pick(15, 12) }
    var toolbarDividerHeight: CGFloat { pick(14, 11) }
    var toolbarHorizontalPadding: CGFloat { pick(8, 6) }
    var toolbarVerticalPadding: CGFloat { pick(4, 2) }
    var toolbarPillCornerRadius: CGFloat { pick(7, 6) }

    // MARK: Footer

    var footerButtonSize: CGFloat { pick(28, 22) }
    var footerButtonIconSize: CGFloat { pick(12, 10) }
    var footerChevronIconSize: CGFloat { pick(9, 8) }
    var footerButtonSpacing: CGFloat { pick(6, 4) }
    var footerInfoBottomPadding: CGFloat { pick(4, 2) }
    var footerActionHorizontalPadding: CGFloat { pick(7, 5) }
    var footerActionVerticalPadding: CGFloat { pick(6, 3) }
    var footerCopyHorizontalPadding: CGFloat { pick(10, 8) }
    var footerCopyVerticalPadding: CGFloat { pick(5, 3) }
    var footerCapsuleSeparatorHeight: CGFloat { pick(16, 13) }
    var footerBugButtonHorizontalPadding: CGFloat { pick(14, 11) }
    var footerBugButtonVerticalPadding: CGFloat { pick(7, 4) }

    // MARK: Type
    //
    // `BuoyFont`'s roles map to the system's semantic text styles, which is
    // right for chrome at the regular density but cannot be scaled by a
    // factor. The compact density therefore names explicit point sizes — the
    // one place in the app where chrome text does, and only because there is
    // no semantic style below `.caption` to step down to.

    var footerInfoFont: Font { isCompact ? .system(size: 9) : BuoyFont.caption }
    var footerActionFont: Font {
        isCompact ? .system(size: 10, weight: .medium) : BuoyFont.secondaryEmphasized
    }
    var footerHintFont: Font { isCompact ? .system(size: 9) : BuoyFont.caption }
    var footerTransferFont: Font { isCompact ? .system(size: 10) : BuoyFont.secondary }

    // MARK: Width minimums
    //
    // Each bar's own horizontal need, so the panel's floor tracks the density
    // the same way its height does. Compact controls take less room across as
    // well as down, and a panel that could only shrink vertically would leave
    // the compact chrome floating in space it no longer needs.

    /// Traffic lights, the two header buttons, and the paddings either side.
    var headerMinimumWidth: CGFloat {
        trafficLightsLeadingPadding
            + (trafficLightsNaturalWidth * trafficLightScale)
            + 12
            + (headerButtonSize * 2) + headerButtonSpacing
            + headerButtonTrailingPadding
    }

    /// Three standard window buttons on AppKit's 23pt pitch.
    private var trafficLightsNaturalWidth: CGFloat { 60 }

    /// Enough title to be worth reading, plus its padding.
    var titleRowMinimumWidth: CGFloat {
        (titleHorizontalPadding * 2) + pick(180, 150)
    }

    /// Seven pill buttons, six 1pt dividers, and the capsule's own padding.
    var toolbarMinimumWidth: CGFloat {
        (toolbarHorizontalPadding * 2) + (toolbarPillWidth * 7) + 6
    }

    /// Two circle buttons on the left and the Copy capsule on the right.
    var footerMinimumWidth: CGFloat {
        (footerActionHorizontalPadding * 2)
            + (footerButtonSize * 2) + footerButtonSpacing
            + pick(104, 88)
    }

    /// The narrowest the panel is allowed to be, independent of what the bars
    /// mechanically need.
    ///
    /// They fit in far less, but a note column that narrow wraps ordinary
    /// prose every few words and the panel stops reading as a place to write.
    /// This used to be set incidentally by the width of the old Settings
    /// overlay; it is stated outright now, because it is a design decision
    /// rather than a consequence of one. It scales with the density for the
    /// same reason the text does — smaller type fits more words per line, so
    /// the comfortable column is narrower.
    var comfortableContentWidth: CGFloat { pick(292, 244) }

    // MARK: Section minimums

    var headerMinimumHeight: CGFloat { pick(70, 54) }
    var toolbarMinimumHeight: CGFloat { pick(36, 30) }
    var footerMinimumHeight: CGFloat { pick(68, 52) }
    var editorMinimumHeight: CGFloat { pick(160, 120) }
}

private struct ChromeMetricsKey: EnvironmentKey {
    static let defaultValue: ChromeMetrics = .regular
}

extension EnvironmentValues {
    var chromeMetrics: ChromeMetrics {
        get { self[ChromeMetricsKey.self] }
        set { self[ChromeMetricsKey.self] = newValue }
    }
}

/// Watches the panel's height and picks the chrome density from it.
///
/// Sits in the background so it never affects layout — the same trick
/// `TitleLaneWidthReader` uses. Reading the height in SwiftUI rather than
/// publishing it from `windowDidResize` is deliberate: the hosting view runs
/// with `sizingOptions = []` specifically to keep SwiftUI out of AppKit's
/// constraint cycle during the Harbor Mode frame animation, and a new
/// AppKit-to-SwiftUI size channel is exactly what that was protecting against.
struct ChromeDensityReader: View {
    @Binding var density: ChromeDensity
    /// The Settings toggle. When on, the density is compact whatever the
    /// panel's height, so a user who simply prefers smaller controls gets them.
    var isForced: Bool
    /// Harbor Mode unmounts this whole tree and animates the frame to pill
    /// size; a density recomputed from those intermediate heights would be
    /// meaningless and would land just as the panel is restoring.
    var isSuspended: Bool
    /// Called only when a *resize* turned compact chrome on, never when the
    /// Settings toggle did — the toggle is a deliberate choice and does not
    /// need announcing or undoing. The value is the window height to go back
    /// to, already raised past the hysteresis exit point so that undoing
    /// really does restore regular chrome rather than landing inside the band
    /// and appearing to do nothing.
    var onAutomaticCompact: ((CGSize) -> Void)? = nil
    /// Called when a resize took the panel back to regular chrome, so anything
    /// said about going compact can stop being said.
    var onAutomaticRegular: (() -> Void)? = nil

    /// The size the panel was last seen at while drawing regular chrome.
    @State private var lastRegularWindowSize = CGSize(
        width: PanelLayoutMetrics.regularChromeWindowWidth,
        height: PanelLayoutMetrics.regularChromeWindowHeight
    )
    /// The first reading establishes the starting density; it is not a change
    /// the user made and must not announce itself.
    @State private var hasReadInitialHeight = false

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { update(glassSize: proxy.size) }
                .onChange(of: proxy.size) { _, size in update(glassSize: size) }
                .onChange(of: isForced) { _, _ in update(glassSize: proxy.size) }
        }
        .allowsHitTesting(false)
    }

    private func update(glassSize: CGSize) {
        guard !isSuspended else { return }
        let inset = PanelLayoutMetrics.glassEdgeInset * 2
        let windowSize = CGSize(width: glassSize.width + inset, height: glassSize.height + inset)
        if density == .regular {
            lastRegularWindowSize = windowSize
        }

        let next = Self.density(forWindowSize: windowSize, isForced: isForced, current: density)
        defer { hasReadInitialHeight = true }
        guard next != density else { return }

        let isFirstReading = !hasReadInitialHeight
        // Per axis: an axis that already has room keeps whatever it is now, so
        // undoing a shrink in one direction does not quietly grow the other.
        // The axis that *is* short goes past its exit threshold rather than
        // merely back to its old value — a size inside the hysteresis band
        // leaves the chrome compact, so undoing would visibly do nothing.
        let restoreSize = CGSize(
            width: windowSize.width < PanelLayoutMetrics.compactChromeExitWidth
                ? max(lastRegularWindowSize.width, PanelLayoutMetrics.compactChromeExitWidth)
                : windowSize.width,
            height: windowSize.height < PanelLayoutMetrics.compactChromeExitHeight
                ? max(lastRegularWindowSize.height, PanelLayoutMetrics.compactChromeExitHeight)
                : windowSize.height
        )

        withAnimation(BuoyMotion.easeOut(0.15)) { density = next }

        guard !isFirstReading, !isForced else { return }
        if next == .compact {
            onAutomaticCompact?(restoreSize)
        } else {
            onAutomaticRegular?()
        }
    }

    /// Hysteresis: compact engages the moment regular chrome no longer fits,
    /// and only lets go once there is a clear margin above that. Without the
    /// gap, a drag parked on the boundary flickers the whole chrome.
    /// Either axis can ask for compact chrome, and regular only comes back
    /// when both have room for it.
    static func density(
        forWindowSize size: CGSize,
        isForced: Bool,
        current: ChromeDensity
    ) -> ChromeDensity {
        if isForced { return .compact }
        switch current {
        case .regular:
            // Half a point of slack: the panel launches at exactly the regular
            // minimum on both axes, and a rounding difference in the measured
            // glass size would otherwise start it in compact chrome.
            let tooShort = size.height < PanelLayoutMetrics.compactChromeEnterHeight - 0.5
            let tooNarrow = size.width < PanelLayoutMetrics.compactChromeEnterWidth - 0.5
            return (tooShort || tooNarrow) ? .compact : .regular
        case .compact:
            let tallEnough = size.height >= PanelLayoutMetrics.compactChromeExitHeight
            let wideEnough = size.width >= PanelLayoutMetrics.compactChromeExitWidth
            return (tallEnough && wideEnough) ? .regular : .compact
        }
    }
}
