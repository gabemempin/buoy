import SwiftUI
import AppKit

/// NSScrollView that never initiates window drag, so text selection works without moving the window.
private final class DragBlockingScrollView: NSScrollView {
    /// Shortest fade the editor ever draws. Larger font sizes scale past it so the
    /// fade always covers a comparable slice of a line rather than clipping one.
    private static let minimumEdgeFadeDistance: CGFloat = 20
    private static let edgeFadeLineMultiple: CGFloat = 1.25

    private let edgeFadeMask = CAGradientLayer()
    private var textChangeObserver: NSObjectProtocol?
    private var lastTopFadeStrength: CGFloat = -1
    private var lastBottomFadeStrength: CGFloat = -1
    private var lastFadeBounds: CGRect = .null
    private var lastFadeDistance: CGFloat = -1

    override var documentView: NSView? {
        didSet { observeDocumentTextChanges() }
    }

    deinit {
        if let textChangeObserver {
            NotificationCenter.default.removeObserver(textChangeObserver)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureEdgeFade()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureEdgeFade()
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override var needsPanelToBecomeKey: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private var accumulatedDeltaX: CGFloat = 0
    private var isTrackingSwipe = false

    /// Shift + scroll accumulation, plus the timestamps that separate one
    /// flick from the next on a device that reports no gesture phase.
    private var accumulatedNavigationDelta: CGFloat = 0
    private var lastWheelNavigation = Date.distantPast
    private var lastWheelEvent = Date.distantPast
    /// Precise devices report a real phase, so a gesture that has already
    /// moved a note stays latched until the fingers lift.
    private var hasNavigatedInCurrentGesture = false

    /// A wheel reports lines, not points, so this counts notches.
    private static let wheelNavigationThreshold: CGFloat = 2
    /// A trackpad or Magic Mouse reports points: match the horizontal swipe
    /// below so both gestures need a comparable amount of travel.
    private static let preciseNavigationThreshold: CGFloat = 50
    /// Keep one continuous spin from flipping through several notes at once.
    private static let wheelNavigationCooldown: TimeInterval = 0.35
    /// A gap this long means the user let go: start the next flick from zero.
    private static let wheelIdleReset: TimeInterval = 0.5

    override func scrollWheel(with event: NSEvent) {
        // Shift + scroll navigates notes on *every* device. This used to be
        // gated on `!event.hasPreciseScrollingDeltas`, on the theory that a
        // trackpad or Magic Mouse could just swipe horizontally instead. But
        // macOS only transposes Shift + scroll onto the X axis for a plain
        // wheel — a precise device already has a horizontal axis, so it keeps
        // reporting Y and the swipe path below (which wants X to dominate)
        // never fired. The gesture was unreachable on exactly the hardware
        // most people use.
        if Self.isNavigationModifier(event.modifierFlags) {
            navigateByScroll(event)
            return
        }

        if event.phase == .began {
            // Initiate tracking if the horizontal intent dominates vertical intent
            isTrackingSwipe = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            accumulatedDeltaX = 0
        }

        if isTrackingSwipe, event.phase == .changed || event.phase == .ended {
            accumulatedDeltaX += event.scrollingDeltaX

            // Threshold is ~50pt for a clean trigger
            if accumulatedDeltaX > 50 {
                NotificationCenter.default.post(name: .buoyPreviousNote, object: nil)
                isTrackingSwipe = false
                accumulatedDeltaX = 0
            } else if accumulatedDeltaX < -50 {
                NotificationCenter.default.post(name: .buoyNextNote, object: nil)
                isTrackingSwipe = false
                accumulatedDeltaX = 0
            }
        }

        if !isTrackingSwipe {
            super.scrollWheel(with: event)
        }
    }

    /// Shift alone. Shift + Cmd and Shift + Option stay out of it so they can
    /// keep whatever meaning AppKit gives them. Caps Lock is ignored rather
    /// than matched exactly, since it has nothing to do with scrolling.
    private static func isNavigationModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.shift)
            && !flags.contains(.command)
            && !flags.contains(.option)
            && !flags.contains(.control)
    }

    /// Turns Shift + scroll into note navigation. The event is consumed either
    /// way, so the editor doesn't also scroll while the user is holding Shift.
    private func navigateByScroll(_ event: NSEvent) {
        // Momentum after a flick is that same gesture coasting, not a new one.
        guard event.momentumPhase == [] else { return }

        // Take whichever axis actually carries the movement. macOS transposes
        // Shift + wheel onto X for a plain mouse but leaves a precise device
        // on Y, and a vertical trackpad swipe always carries a little X
        // jitter — so compare magnitudes rather than testing X against zero,
        // which would let that jitter stand in for the real movement.
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        let delta = abs(deltaX) > abs(deltaY) ? deltaX : deltaY

        if event.hasPreciseScrollingDeltas {
            navigateByPreciseScroll(delta, phase: event.phase)
        } else {
            navigateByWheel(delta)
        }
    }

    /// Trackpad and Magic Mouse. These report a gesture phase, so the gesture's
    /// own start and end do the separating: one swipe moves exactly one note,
    /// however far it runs.
    private func navigateByPreciseScroll(_ delta: CGFloat, phase: NSEvent.Phase) {
        if phase.contains(.began) {
            accumulatedNavigationDelta = 0
            hasNavigatedInCurrentGesture = false
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            accumulatedNavigationDelta = 0
            hasNavigatedInCurrentGesture = false
            return
        }

        guard !hasNavigatedInCurrentGesture else { return }
        accumulatedNavigationDelta += delta
        guard abs(accumulatedNavigationDelta) >= Self.preciseNavigationThreshold else { return }

        postNavigation(forward: accumulatedNavigationDelta < 0)
        hasNavigatedInCurrentGesture = true
        accumulatedNavigationDelta = 0
    }

    /// A plain wheel mouse. No phase at all, so time has to do the separating:
    /// a cooldown after a jump, and an idle gap that starts the next flick
    /// from zero.
    private func navigateByWheel(_ delta: CGFloat) {
        let now = Date()
        defer { lastWheelEvent = now }

        // Still settling from the last jump: swallow the rest of the spin
        // instead of letting it queue up into another one.
        guard now.timeIntervalSince(lastWheelNavigation) > Self.wheelNavigationCooldown else {
            accumulatedNavigationDelta = 0
            return
        }
        if now.timeIntervalSince(lastWheelEvent) > Self.wheelIdleReset {
            accumulatedNavigationDelta = 0
        }

        guard delta != 0 else { return }
        accumulatedNavigationDelta += delta
        guard abs(accumulatedNavigationDelta) >= Self.wheelNavigationThreshold else { return }

        postNavigation(forward: accumulatedNavigationDelta < 0)
        accumulatedNavigationDelta = 0
        lastWheelNavigation = now
    }

    /// Positive delta means "back", matching the horizontal swipe above where
    /// a rightward swipe reaches the previous note.
    private func postNavigation(forward: Bool) {
        NotificationCenter.default.post(
            name: forward ? .buoyNextNote : .buoyPreviousNote,
            object: nil
        )
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        syncDocumentViewGeometry()
        updateEdgeFade()
    }

    override func tile() {
        super.tile()
        syncDocumentViewGeometry()
        updateEdgeFade()
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        updateEdgeFade()
    }

    private func configureEdgeFade() {
        wantsLayer = true
        edgeFadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        edgeFadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        edgeFadeMask.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "colors": NSNull(),
            "locations": NSNull()
        ]
        layer?.mask = edgeFadeMask
    }

    /// Height of the fade at each edge, scaled to the current line height so the
    /// softened band stays proportional across the 11–20pt font-size range.
    private var edgeFadeDistance: CGFloat {
        guard let textView = documentView as? BuoyTextView,
              let layoutManager = textView.layoutManager else {
            return Self.minimumEdgeFadeDistance
        }
        let lineHeight = layoutManager.defaultLineHeight(
            for: NSFont.systemFont(ofSize: textView.fontSize)
        )
        return max(Self.minimumEdgeFadeDistance, lineHeight * Self.edgeFadeLineMultiple)
    }

    /// Text edits change the scrollable range without moving the clip view, so the
    /// fade has to be recomputed outside the scroll and layout callbacks too.
    func refreshEdgeFade() {
        updateEdgeFade()
    }

    private func observeDocumentTextChanges() {
        if let textChangeObserver {
            NotificationCenter.default.removeObserver(textChangeObserver)
            self.textChangeObserver = nil
        }
        guard let textView = documentView as? BuoyTextView else { return }
        textChangeObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.updateEdgeFade()
        }
    }

    /// 0 at the very end of the scroll range, ramping to a full fade once one
    /// fade-width of content sits past the edge. Smoothstepped so the shadow
    /// builds in softly instead of popping on at the first scroll event.
    private func fadeStrength(forDistance distance: CGFloat, fadeDistance: CGFloat) -> CGFloat {
        guard fadeDistance > 0 else { return 0 }
        let progress = min(max(distance / fadeDistance, 0), 1)
        let eased = progress * progress * (3 - (2 * progress))
        // Quantize to the mask's 8-bit alpha resolution so scroll frames that
        // land on the same visual result can skip the layer update entirely.
        return (eased * 255).rounded() / 255
    }

    private func updateEdgeFade() {
        guard bounds.height > 0 else { return }
        if layer?.mask !== edgeFadeMask {
            layer?.mask = edgeFadeMask
            lastFadeBounds = .null
        }

        let clipBounds = contentView.bounds
        let documentRect = contentView.documentRect
        let fadeDistance = edgeFadeDistance

        // Both edges are measured the same way — points of travel still available
        // in that direction — so the top and bottom fades build at the same rate.
        // Rubber-band overscroll can push either past its limit; the ramp clamps.
        let travelAbove = clipBounds.minY - documentRect.minY
        let travelBelow: CGFloat
        if let textView = documentView as? BuoyTextView,
           let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            // Measure against laid-out glyphs, not the document view, which is
            // padded out to fill the clip view. AppKit's extra line fragment is
            // only the caret row after the document; counting it keeps the final
            // line faded while it is still genuinely below the viewport.
            layoutManager.ensureLayout(for: textContainer)
            let laidOutTextBottom = textView.textContainerOrigin.y
                + layoutManager.usedRect(for: textContainer).maxY
            travelBelow = laidOutTextBottom - textView.visibleRect.maxY
        } else {
            let maximumOffsetY = max(documentRect.minY, documentRect.maxY - clipBounds.height)
            travelBelow = maximumOffsetY - clipBounds.minY
        }

        let topStrength = fadeStrength(forDistance: travelAbove, fadeDistance: fadeDistance)
        let bottomStrength = fadeStrength(forDistance: travelBelow, fadeDistance: fadeDistance)

        guard topStrength != lastTopFadeStrength
                || bottomStrength != lastBottomFadeStrength
                || fadeDistance != lastFadeDistance
                || bounds != lastFadeBounds else { return }
        lastTopFadeStrength = topStrength
        lastBottomFadeStrength = bottomStrength
        lastFadeDistance = fadeDistance
        lastFadeBounds = bounds

        let opaque = NSColor.black.cgColor
        let fadeLocation = min(0.25, fadeDistance / bounds.height)

        edgeFadeMask.frame = bounds
        // This scroll view and its backing layer are flipped, so the gradient's
        // first color is the visual top and its final color is the visual bottom.
        edgeFadeMask.colors = [
            NSColor.black.withAlphaComponent(1 - topStrength).cgColor,
            opaque,
            opaque,
            NSColor.black.withAlphaComponent(1 - bottomStrength).cgColor
        ]
        edgeFadeMask.locations = [
            0,
            NSNumber(value: fadeLocation),
            NSNumber(value: 1 - fadeLocation),
            1
        ]
    }

    private func syncDocumentViewGeometry() {
        guard let textView = documentView as? BuoyTextView else { return }

        let contentSize = self.contentSize
        guard contentSize.width > 0, contentSize.height > 0 else { return }

        let targetHeight = max(textView.frame.height, contentSize.height)
        if abs(textView.frame.width - contentSize.width) > 0.5
            || abs(textView.frame.height - targetHeight) > 0.5 {
            textView.frame = NSRect(origin: .zero, size: NSSize(width: contentSize.width, height: targetHeight))
        }

        let targetMinSize = NSSize(width: 0, height: contentSize.height)
        if textView.minSize != targetMinSize {
            textView.minSize = targetMinSize
        }

        let targetContainerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        if textView.textContainer?.containerSize != targetContainerSize {
            textView.textContainer?.containerSize = targetContainerSize
        }
        textView.textContainer?.widthTracksTextView = true
        updateEdgeFade()
    }
}

struct EditorView: NSViewRepresentable {
    var rtfData: Data
    var fontSize: CGFloat
    /// Rendering scale for compact chrome, applied as scroll-view
    /// magnification. Deliberately *not* folded into `fontSize`: font size is
    /// an attribute of the text storage, so shrinking it there would rewrite
    /// and re-save every note's RTF each time the panel crossed the compact
    /// threshold. Magnification is display-only and the document never moves.
    var magnification: CGFloat = 1
    var usesDarkAppearance: Bool
    var noteID: String
    var placeholder: String = "Start typing…"
    var onSelectionChange: ((String) -> Void)?
    var onContentChange: ((Data) -> Void)?
    var textViewRef: ((BuoyTextView) -> Void)?

    func makeCoordinator() -> TextViewCoordinator {
        let c = TextViewCoordinator()
        c.onSelectionChange = onSelectionChange
        c.onContentChange = onContentChange
        return c
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = DragBlockingScrollView()
        scrollView.borderType = .noBorder
        // Start hidden so the scroller doesn't flash during the slide-in transition.
        // Re-enabled after the spring animation (~0.3s response) settles.
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.autoresizesSubviews = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        // Set programmatically only; there is no pinch-to-zoom in a note.
        scrollView.allowsMagnification = false
        scrollView.magnification = magnification

        let contentSize = scrollView.contentSize
        let initialWidth = max(
            contentSize.width,
            PanelLayoutMetrics.minimumContentWidth(for: .compact) - (PanelLayoutMetrics.windowPadding * 2)
        )
        let initialHeight = max(contentSize.height, ChromeMetrics.compact.editorMinimumHeight)

        let textView = BuoyTextView(
            frame: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight)
        )
        textView.fontSize = fontSize
        textView.usesDarkAppearance = usesDarkAppearance
        textView.minSize = NSSize(width: 0, height: initialHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: initialWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.buoyDelegate = context.coordinator

        scrollView.documentView = textView
        scrollView.layoutSubtreeIfNeeded()
        context.coordinator.currentNoteID = noteID
        textViewRef?(textView)

        context.coordinator.setLoadingContent(true)
        textView.loadRTF(rtfData)
        context.coordinator.setLoadingContent(false)
        scrollView.refreshEdgeFade()

        // Re-enable the scroller after the slide-in transition finishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            scrollView.hasVerticalScroller = true
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? BuoyTextView else { return }

        scrollView.layoutSubtreeIfNeeded()
        textViewRef?(textView)

        if textView.fontSize != fontSize {
            textView.fontSize = fontSize
            // Line height drives the fade height, and relaid-out text changes how
            // much is left to scroll.
            (scrollView as? DragBlockingScrollView)?.refreshEdgeFade()
        }

        if abs(scrollView.magnification - magnification) > 0.001 {
            scrollView.magnification = magnification
            // The text container tracks the clip view's width in document
            // coordinates, which magnification changes, so the text reflows
            // and the amount left to scroll with it.
            scrollView.layoutSubtreeIfNeeded()
            (scrollView as? DragBlockingScrollView)?.refreshEdgeFade()
        }

        if textView.usesDarkAppearance != usesDarkAppearance {
            textView.usesDarkAppearance = usesDarkAppearance
        }

        if textView.placeholderString != placeholder {
            textView.placeholderString = placeholder
        }

        if context.coordinator.currentNoteID != noteID {
            context.coordinator.currentNoteID = noteID
            // Temporarily hide the scroller so the content swap doesn't flash it.
            scrollView.hasVerticalScroller = false
            context.coordinator.setLoadingContent(true)
            textView.loadRTF(rtfData)
            context.coordinator.setLoadingContent(false)
            (scrollView as? DragBlockingScrollView)?.refreshEdgeFade()
            // Re-enable after AppKit's scroller-flash window has passed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                scrollView.hasVerticalScroller = true
            }
        }

        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onContentChange = onContentChange
    }
}

// MARK: - Coordinator BuoyTextViewDelegate conformance

extension TextViewCoordinator: BuoyTextViewDelegate {
    func textViewDidChange(_ textView: BuoyTextView) {
        guard !isLoadingContent else { return }
        if let rtf = textView.rtfContent() {
            onContentChange?(rtf)
        }
    }

    func textViewSelectionDidChange(_ textView: BuoyTextView) {
        onSelectionChange?(textView.selectedPlainText(for: textView.selectedRange()))
    }

    func textViewRequestShowLinkDialog(context: LinkEditingContext) {
        NotificationCenter.default.post(name: .showLinkDialog, object: context)
    }
}

extension Notification.Name {
    static let showLinkDialog = Notification.Name("BuoyShowLinkDialog")
}
