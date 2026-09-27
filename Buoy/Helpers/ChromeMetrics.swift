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
/// alone claim 174pt, which is most of a short panel. Controls and rendered
/// text scale together; the stored editor font size stays unchanged.
struct ChromeMetrics: Equatable {
    var compactness: CGFloat

    init(density: ChromeDensity) {
        compactness = density == .compact ? 1 : 0
    }

    init(compactness: CGFloat) {
        self.compactness = min(1, max(0, compactness))
    }

    static let regular = ChromeMetrics(density: .regular)
    static let compact = ChromeMetrics(density: .compact)

    private func pick(_ regular: CGFloat, _ compact: CGFloat) -> CGFloat {
        regular + (compact - regular) * compactness
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

    var footerInfoFont: Font {
        .system(size: pick(NSFont.preferredFont(forTextStyle: .caption1, options: [:]).pointSize, 9))
    }
    var footerActionFont: Font {
        .system(size: pick(NSFont.preferredFont(forTextStyle: .subheadline, options: [:]).pointSize, 10), weight: .medium)
    }
    var footerHintFont: Font { footerInfoFont }
    var footerTransferFont: Font {
        .system(size: pick(NSFont.preferredFont(forTextStyle: .subheadline, options: [:]).pointSize, 10))
    }

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

/// Reads the real window size without pushing layout constraints back into AppKit.
/// Scaling follows the pointer directly, with no mode animation or notification.
struct ChromeDensityReader: View {
    @Binding var compactness: CGFloat
    let presentation: PanelPresentationModel

    /// Harbor Mode and the sweep in and out of it pass through sizes that say
    /// nothing about the panel the user chose.
    private var isSuspended: Bool {
        presentation.isMinimized || presentation.harborTransitionGlassSize != nil
    }

    private var windowSize: CGSize { presentation.windowSize }

    var body: some View {
        Color.clear
            .onAppear { update() }
            .onChange(of: windowSize) { _, _ in update() }
            .onChange(of: isSuspended) { _, _ in update() }
            .allowsHitTesting(false)
    }

    private func update() {
        guard !isSuspended else { return }
        let widthFraction = (PanelLayoutMetrics.regularChromeWindowWidth - windowSize.width)
            / (PanelLayoutMetrics.regularChromeWindowWidth - PanelLayoutMetrics.minimumWindowWidth)
        let heightFraction = (PanelLayoutMetrics.regularChromeWindowHeight - windowSize.height)
            / (PanelLayoutMetrics.regularChromeWindowHeight - PanelLayoutMetrics.minimumWindowHeight)
        let next = min(1, max(0, widthFraction, heightFraction))
        guard next != compactness else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { compactness = next }
    }
}

/// Lays the full panel out at a fixed glass size during the Harbor sweep,
/// clipped to the glass's rounded shape, so the window reveals or covers the
/// content instead of re-laying it out every frame.
///
/// One modifier chain whether or not a sweep is running — `nil` just leaves
/// the frame unconstrained. An `if let` here made SwiftUI swap between two
/// branches, which gives the content a new identity: the whole panel, editor
/// and all, was torn down and rebuilt as the fold began (leaving an empty
/// glass rectangle on screen for a moment) and again as a restore finished.
struct HarborTransitionLayout: ViewModifier {
    let size: CGSize?
    let alignment: Alignment

    func body(content: Content) -> some View {
        content
            .frame(width: size?.width, height: size?.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .clipShape(RoundedRectangle(cornerRadius: PanelLayoutMetrics.windowCornerRadius))
    }
}
