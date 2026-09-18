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
    var onAutomaticCompact: ((CGFloat) -> Void)? = nil

    /// The tallest the panel has been seen at while drawing regular chrome.
    @State private var lastRegularWindowHeight: CGFloat = PanelLayoutMetrics.regularChromeWindowHeight
    /// The first reading establishes the starting density; it is not a change
    /// the user made and must not announce itself.
    @State private var hasReadInitialHeight = false

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { update(glassHeight: proxy.size.height) }
                .onChange(of: proxy.size.height) { _, height in update(glassHeight: height) }
                .onChange(of: isForced) { _, _ in update(glassHeight: proxy.size.height) }
        }
        .allowsHitTesting(false)
    }

    private func update(glassHeight: CGFloat) {
        guard !isSuspended else { return }
        let windowHeight = glassHeight + (PanelLayoutMetrics.glassEdgeInset * 2)
        if density == .regular {
            lastRegularWindowHeight = windowHeight
        }

        let next = Self.density(
            forWindowHeight: windowHeight,
            isForced: isForced,
            current: density
        )
        defer { hasReadInitialHeight = true }
        guard next != density else { return }

        let announces = next == .compact && !isForced && hasReadInitialHeight
        let restoreHeight = max(lastRegularWindowHeight, PanelLayoutMetrics.compactChromeExitHeight)

        withAnimation(BuoyMotion.easeOut(0.15)) { density = next }

        if announces {
            onAutomaticCompact?(restoreHeight)
        }
    }

    /// Hysteresis: compact engages the moment regular chrome no longer fits,
    /// and only lets go once there is a clear margin above that. Without the
    /// gap, a drag parked on the boundary flickers the whole chrome.
    static func density(
        forWindowHeight height: CGFloat,
        isForced: Bool,
        current: ChromeDensity
    ) -> ChromeDensity {
        if isForced { return .compact }
        switch current {
        case .regular:
            return height < PanelLayoutMetrics.compactChromeEnterHeight ? .compact : .regular
        case .compact:
            return height >= PanelLayoutMetrics.compactChromeExitHeight ? .regular : .compact
        }
    }
}
