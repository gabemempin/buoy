import SwiftUI
import AppKit

// MARK: - NSTextField wrapper that explicitly handles ⌘A

private final class TitleNSTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .help, .capsLock])
        if mods == .command && event.keyCode == 0 { // keyCode 0 = "a"
            guard let editor = currentEditor() else {
                return super.performKeyEquivalent(with: event)
            }
            editor.selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct TitleTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var isFocused: Bool
    /// Blanks the field's own glyphs so an overlay (the bug-report shimmer, or
    /// the scrolling title) can stand in for them without doubling up.
    var hidesText: Bool = false
    var onEditingChanged: (Bool) -> Void = { _ in }
    var fontSize: CGFloat = 19
    @Environment(\.colorScheme) var colorScheme

    func makeNSView(context: Context) -> TitleNSTextField {
        let field = TitleNSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold, width: .expanded)
        field.textColor = TitleTextField.textColor(for: colorScheme)
        field.alignment = .center
        // No focus ring by design. AppKit's masks to the cell frame, which on a
        // field spanning the whole panel is a heavy box around mostly empty
        // space, and a drawn substitute (ring or underline) read as clutter above
        // the title. The insertion caret already marks focus for sighted keyboard
        // users, and VoiceOver reports it from the accessibility label either way.
        field.focusRingType = .none
        field.setAccessibilityLabel("Note title")
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submitted(_:))
        return field
    }

    func updateNSView(_ nsView: TitleNSTextField, context: Context) {
        // Re-applied on every update so a chrome-density change resizes the
        // title in place rather than only on the next remount.
        if nsView.font?.pointSize != fontSize {
            nsView.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold, width: .expanded)
        }
        if nsView.stringValue != text {
            // AppKit can notify the field delegate when its string value is
            // refreshed from SwiftUI. That is a model -> view update, not a
            // user edit; forwarding it through the binding would call
            // NoteStore.saveTitle and permanently lock a brand-new note
            // before its content can reach the auto-title thresholds.
            context.coordinator.isApplyingModelValue = true
            nsView.stringValue = text
            context.coordinator.isApplyingModelValue = false
        }
        nsView.textColor = hidesText ? .clear : TitleTextField.textColor(for: colorScheme)
        if isFocused && nsView.window?.firstResponder !== nsView.currentEditor() {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    /// Single source for the title colour, so the field and any overlay standing
    /// in for it cannot drift apart.
    static func textColor(for colorScheme: ColorScheme) -> NSColor {
        BuoyTheme.current.accentText(isDark: colorScheme == .dark)
    }

    /// Colour of the auto-title "thinking" glow: the title's own colour,
    /// bloomed. White in dark mode, where a white halo is the only thing that
    /// reads against the panel; the accent in light mode, where white would
    /// vanish into the background.
    static func thinkingGlowColor(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: textColor(for: colorScheme))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TitleTextField
        var isApplyingModelValue = false

        init(parent: TitleTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard !isApplyingModelValue else { return }
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onEditingChanged(true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onEditingChanged(false)
        }

        @objc func submitted(_ sender: Any?) { parent.onSubmit() }
    }
}

// MARK: - HeaderView

struct HeaderView: View {
    @Binding var title: String
    /// Toggle this value to auto-focus + select-all the title field (e.g. on new note).
    var focusTitleTrigger: Bool
    var onClose: () -> Void
    var onMinimize: () -> Void
    var onExpand: () -> Void
    var onAllNotes: () -> Void
    var onNewNote: () -> Void
    var focusEditor: () -> Void
    var onHeaderDoubleClick: (() -> Void)? = nil
    var dragEnabled: Bool = true
    var isBugReport: Bool = false
    /// Set the instant an auto-generated title lands, to play the reveal
    /// once. `nil` the rest of the time.
    var titleReveal: NoteStore.TitleReveal?
    var onRevealFinished: () -> Void = {}
    /// True while an auto-title request is running for the current note —
    /// plays the "thinking" shimmer over the title.
    var titleThinking: Bool = false
    /// The countdown shown in place of the title while a Harbor timer runs.
    var timerTitle: String? = nil
    var isTimerPaused: Bool = false
    /// Folds the panel into Harbor Mode, where the timer's controls live.
    var onTimerTitleClick: () -> Void = {}

    @FocusState private var titleFocused: Bool
    @State private var isEditingTitle = false
    @State private var titleLaneWidth: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.chromeMetrics) private var metrics

    /// Scroll the title only when it cannot fit *and* nobody is editing it —
    /// text sliding out from under the caret would be unusable.
    private var showsScrollingTitle: Bool {
        guard !isBugReport, !isEditingTitle, titleLaneWidth > 0 else { return false }
        // Measured in the face the field is actually drawing in at this
        // density, or the marquee kicks in on a title that fits.
        return PanelLayoutMetrics.textWidth(title, font: metrics.titleFont) > titleLaneWidth
    }

    /// The reveal wins over the marquee for its duration — an auto-generated
    /// title is capped at three words, so the two states shouldn't collide.
    private var showsReveal: Bool {
        titleReveal != nil && !isBugReport && !isEditingTitle
    }

    /// Thinking only shows once the reveal (if any is queued) has had its
    /// turn — a request finishing while the previous reveal is still playing
    /// shouldn't cut it off.
    private var showsThinking: Bool {
        titleThinking && !showsReveal && !isBugReport && !isEditingTitle
    }

    var body: some View {
        VStack(spacing: metrics.headerRowSpacing) {
            HStack(spacing: 0) {
                TrafficLightsView(
                    onClose: onClose,
                    onMinimize: onMinimize,
                    onExpand: onExpand,
                    scale: metrics.trafficLightScale
                )
                .padding(.leading, metrics.trafficLightsLeadingPadding)

                Spacer()

                if !isBugReport {
                    HStack(spacing: metrics.headerButtonSpacing) {
                        HeaderButton(systemImage: "line.horizontal.3", tooltip: "All Notes", action: onAllNotes)
                        HeaderButton(systemImage: "plus",              tooltip: "New Note",  action: onNewNote)
                    }
                    .padding(.trailing, metrics.headerButtonTrailingPadding)
                }
            }
            .frame(height: metrics.headerControlRowHeight)
            .padding(.top, metrics.headerTopPadding)
            .background(dragEnabled ? WindowDragHandle(onDoubleClick: onHeaderDoubleClick) : nil)

            Group {
                if let timerTitle {
                    Button(action: onTimerTitleClick) {
                        Text(timerTitle)
                            .font(Font(metrics.titleFont))
                            .monospacedDigit()
                            .foregroundStyle(Color(nsColor: TitleTextField.textColor(for: colorScheme)))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: metrics.titleMinHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, metrics.titleHorizontalPadding)
                    .help("Show timer controls in Harbor Mode")
                    .pointingHandCursor()
                    .accessibilityLabel(isTimerPaused ? "Timer paused" : "Timer")
                    .accessibilityValue("\(timerTitle) remaining")
                    .accessibilityHint("Opens Harbor Mode, where you can pause or stop the timer.")
                } else {
                    ZStack {
                        TitleTextField(
                            text: $title,
                            placeholder: "Untitled",
                            onSubmit: focusEditor,
                            isFocused: titleFocused,
                            // Not hidden while thinking: the glow layers *over* the
                            // real text, which is what keeps the letters from
                            // re-tracking when it starts.
                            hidesText: isBugReport || showsReveal || showsScrollingTitle,
                            onEditingChanged: { isEditingTitle = $0 },
                            fontSize: metrics.titleFontSize
                        )
                        .frame(maxWidth: .infinity, minHeight: metrics.titleMinHeight)
                        // Measured *inside* the padding: the marquee below re-applies the
                        // same padding, so reading the outer width would make the overlay
                        // 24pt wider than the row and push the whole panel out of shape.
                        .background(TitleLaneWidthReader(width: $titleLaneWidth))
                        .padding(.horizontal, metrics.titleHorizontalPadding)

                        if isBugReport {
                            AnimatedBugTitle(title: title, fontSize: metrics.titleFontSize)
                                .frame(maxWidth: .infinity, minHeight: metrics.titleMinHeight)
                                .padding(.horizontal, metrics.titleHorizontalPadding)
                                .allowsHitTesting(false)
                        } else if showsReveal, let titleReveal {
                            TitleRevealText(
                                title: titleReveal.title,
                                color: Color(nsColor: TitleTextField.textColor(for: colorScheme)),
                                fontSize: metrics.titleFontSize,
                                onFinished: onRevealFinished
                            )
                            .id(titleReveal.id)
                            .frame(maxWidth: .infinity, minHeight: metrics.titleMinHeight)
                            .padding(.horizontal, metrics.titleHorizontalPadding)
                            .allowsHitTesting(false)
                        } else if showsScrollingTitle {
                            MarqueeText(
                                text: title,
                                font: metrics.titleFont,
                                color: Color(nsColor: TitleTextField.textColor(for: colorScheme)),
                                availableWidth: titleLaneWidth,
                                restingAlignment: .center
                            )
                            .frame(minHeight: metrics.titleMinHeight)
                            .padding(.horizontal, metrics.titleHorizontalPadding)
                            .allowsHitTesting(false)
                        }

                        // Layered on top of whatever is drawing the title rather than
                        // replacing it, so starting the glow can't shift the letters.
                        if showsThinking {
                            TitleThinkingGlow(
                                title: title,
                                color: TitleTextField.thinkingGlowColor(for: colorScheme),
                                fontSize: metrics.titleFontSize
                            )
                            .frame(maxWidth: .infinity, minHeight: metrics.titleMinHeight)
                            .padding(.horizontal, metrics.titleHorizontalPadding)
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
            .padding(.bottom, metrics.titleBottomPadding)
        }
        .background(dragEnabled ? WindowDragHandle() : nil)
        .onChange(of: focusTitleTrigger) { _, _ in
            titleFocused = true
            DispatchQueue.main.async {
                (NSApp.keyWindow?.firstResponder as? NSText)?.selectAll(nil)
            }
        }
    }
}

/// Reports the width the title actually gets, so the header can tell whether the
/// title overflows it. Sits in the background so it never affects layout.
private struct TitleLaneWidthReader: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
        }
    }
}

// MARK: - Shimmer Title

/// Sweeps a moving highlight across a title, base and highlight colours
/// supplied by the caller. Drives both the Bug Report shimmer (`AnimatedBugTitle`,
/// blue/yellow) and the auto-title "thinking" shimmer (accent tones).
struct ShimmerTitle: View {
    let title: String
    let base: Color
    let highlight: Color
    var fontSize: CGFloat = 19
    /// Seconds for one sweep across the title.
    var sweepDuration: TimeInterval = 2.5

    /// The sweeping highlight is continuous movement, so Reduce Motion parks it
    /// mid-title instead of animating. Read from the environment rather than
    /// `BuoyMotion` so flipping the setting re-renders immediately.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// When this shimmer appeared. The phase is measured from here rather than
    /// from absolute time: an always-on shimmer (Bug Report) can't tell the
    /// difference, but a short-lived one (the auto-title "thinking" sweep)
    /// would otherwise pop into view at whatever point the wall clock happened
    /// to be at — the highlight appearing already mid-title, out of nowhere.
    @State private var startDate = Date()

    var body: some View {
        if reduceMotion {
            frame(phase: 0.5)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                frame(phase: phase(for: timeline.date))
            }
            .onAppear { startDate = Date() }
        }
    }

    private func phase(for date: Date) -> CGFloat {
        let elapsed = max(0, date.timeIntervalSince(startDate))
        return CGFloat(elapsed.truncatingRemainder(dividingBy: sweepDuration) / sweepDuration)
    }

    private func frame(phase: CGFloat) -> some View {
        let displayTitle = title.isEmpty ? "Untitled" : title
        let font = Font(NSFont.systemFont(ofSize: fontSize, weight: fontSize > 19 ? .bold : .semibold, width: .expanded))

        return ZStack {
            Text(displayTitle)
                .font(font)
                .lineLimit(1)
                .foregroundStyle(base)

            // Top layer, revealed by the moving highlight.
            Text(displayTitle)
                .font(font)
                .lineLimit(1)
                .foregroundStyle(highlight)
                .mask(TravellingSweep(phase: phase))
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

/// The blurred blob that travels across a title, used as a mask by both the
/// Bug Report shimmer and the auto-title glow.
private struct TravellingSweep: View {
    let phase: CGFloat

    var body: some View {
        GeometryReader { geo in
            Ellipse()
                .fill(Color.white)
                .frame(width: 100, height: geo.size.height + 12)
                .blur(radius: 15)
                .offset(x: phase * (geo.size.width + 200) - 100)
        }
    }
}

/// A travelling glow drawn *around* the title's glyphs, layered on top of the
/// real title field rather than replacing it.
///
/// Two reasons it works this way. White text has no headroom to be lightened
/// from the inside, so a sweep across the glyph fills is invisible in dark
/// mode. And standing in for the field with a SwiftUI `Text` — the way the
/// marquee and the Bug Report shimmer do — re-tracks the letters slightly,
/// which is glaring under a title that is otherwise sitting still. Drawing
/// only a blurred copy and leaving the field on screen avoids both.
struct TitleThinkingGlow: View {
    let title: String
    let color: Color
    var fontSize: CGFloat = 19
    var sweepDuration: TimeInterval = 1.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()

    var body: some View {
        if reduceMotion {
            glow(phase: 0.5)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                glow(phase: phase(for: timeline.date))
            }
            .onAppear { startDate = Date() }
        }
    }

    private func phase(for date: Date) -> CGFloat {
        let elapsed = max(0, date.timeIntervalSince(startDate))
        return CGFloat(elapsed.truncatingRemainder(dividingBy: sweepDuration) / sweepDuration)
    }

    /// Room around the text for the blur to spread into. The mask can only
    /// cover the view's own bounds, so without this the halo — which is the
    /// entire effect — gets cut off square at the text's bounding box.
    private static let spill: CGFloat = 12

    private func glow(phase: CGFloat) -> some View {
        let displayTitle = title.isEmpty ? "Untitled" : title
        let font = Font(NSFont.systemFont(ofSize: fontSize, weight: .semibold, width: .expanded))

        return Text(displayTitle)
            .font(font)
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(Self.spill)
            // The blur spreads past the glyph edges; masked to the moving
            // blob, that spill is the only part that shows around the real
            // text sitting on top of it.
            .blur(radius: 6)
            .mask(TravellingSweep(phase: phase))
            // Hand the layout its original size back. The halo keeps drawing
            // outside those bounds — nothing here clips — so it bleeds softly
            // past the title instead of stopping at an edge.
            .padding(-Self.spill)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }
}

/// The Bug Report title's shimmer: the theme's accent, swept by a glint in
/// its complementary hue. With the system blue that is blue and amber, close
/// to the fixed blue/yellow it used to be; a custom accent gets its own pair.
struct AnimatedBugTitle: View {
    let title: String
    var fontSize: CGFloat = 19

    @Environment(\.buoyTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = theme.bugReportShimmer(isDark: colorScheme == .dark)
        ShimmerTitle(
            title: title,
            base: Color(nsColor: colors.base),
            highlight: Color(nsColor: colors.highlight),
            fontSize: fontSize
        )
    }
}

// MARK: - Auto-Title Reveal

/// Fades an AI-generated title's glyphs in one at a time, left to right —
/// the visible signal that Buoy just renamed this note.
///
/// Drawn as a *single* `Text` run through a `TextRenderer`, not as a stack of
/// per-character `Text`s. That distinction matters: laying each character out
/// on its own throws away kerning and the expanded face's letter spacing, so
/// when the overlay handed back to the real `NSTextField` every glyph visibly
/// snapped into a different position. One shaped run means the resting state
/// here is already pixel-for-pixel what the field draws.
///
/// Plays once per instance: give it a fresh `.id()` (`HeaderView` keys it on
/// `TitleReveal.id`) so a second auto-title later replays from the start.
struct TitleRevealText: View {
    let title: String
    let color: Color
    var fontSize: CGFloat = 19
    var onFinished: () -> Void = {}

    /// A per-glyph stagger is movement, so Reduce Motion substitutes a single
    /// short crossfade for the whole title instead.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false

    /// How long one glyph takes to arrive, and how far apart their starts are.
    private static let glyphDuration: TimeInterval = 0.18
    private static let staggerPerGlyph: TimeInterval = 0.02
    private static let reducedMotionDuration: TimeInterval = 0.12

    private var totalDuration: TimeInterval {
        reduceMotion
            ? Self.reducedMotionDuration
            : Self.glyphDuration + Double(max(0, title.count - 1)) * Self.staggerPerGlyph
    }

    var body: some View {
        Text(title)
            .font(Font(NSFont.systemFont(ofSize: fontSize, weight: .semibold, width: .expanded)))
            .foregroundStyle(color)
            .lineLimit(1)
            .modifier(RevealRendererModifier(
                progress: isRevealed ? 1 : 0,
                // Each glyph's own fade, as a fraction of the whole timeline.
                glyphFraction: totalDuration > 0
                    ? min(1, Self.glyphDuration / totalDuration)
                    : 1,
                isEnabled: !reduceMotion
            ))
            .opacity(reduceMotion && !isRevealed ? 0 : 1)
            .multilineTextAlignment(.center)
            .onAppear {
                // Drive the 0 -> 1 change explicitly, one runloop turn after
                // this view is inserted. Setting it straight from `onAppear`
                // and relying on `.animation(value:)` is a coin flip: the
                // state change can land inside the same transaction that
                // inserts the view, and SwiftUI then commits it with no
                // animation at all, so the title simply pops in fully drawn.
                // That is what made the reveal play only sometimes.
                DispatchQueue.main.async {
                    withAnimation(
                        reduceMotion
                            ? BuoyMotion.easeOut(Self.reducedMotionDuration)
                            : .easeOut(duration: totalDuration)
                    ) {
                        isRevealed = true
                    }
                    // Scheduled from here, not from `onAppear`, so the
                    // hand-back can never beat the animation it is timing.
                    DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
                        onFinished()
                    }
                }
            }
    }
}

/// Applies `TitleRevealRenderer` while the reveal is playing, and gets out of
/// the way entirely under Reduce Motion so the text draws by the normal path.
private struct RevealRendererModifier: ViewModifier {
    var progress: Double
    var glyphFraction: Double
    var isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.textRenderer(
                TitleRevealRenderer(progress: progress, glyphFraction: glyphFraction)
            )
        } else {
            content
        }
    }
}

/// Draws a text run one glyph at a time, each fading up from slightly below
/// with a little blur, staggered left to right.
///
/// Works on the *laid-out* run rather than on separate views, so the glyphs
/// sit exactly where normal text layout puts them the whole way through — no
/// reflow when the animation ends.
private struct TitleRevealRenderer: TextRenderer, Animatable {
    /// 0 = nothing drawn yet, 1 = fully revealed.
    var progress: Double
    /// How much of the timeline a single glyph's own fade occupies.
    var glyphFraction: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let slices = layout.flatMap { $0 }.flatMap { $0 }
        guard !slices.isEmpty else { return }

        let fade = max(0.0001, min(1, glyphFraction))
        let lastStart = max(0, 1 - fade)

        for (index, slice) in slices.enumerated() {
            let start = slices.count > 1
                ? (Double(index) / Double(slices.count - 1)) * lastStart
                : 0
            let local = min(1, max(0, (progress - start) / fade))

            var copy = context
            copy.opacity = local
            if local < 1 {
                copy.translateBy(x: 0, y: (1 - local) * 4)
                copy.addFilter(.blur(radius: (1 - local) * 3))
            }
            copy.draw(slice)
        }
    }
}

// MARK: - Header Button

private struct HeaderButton: View {
    let systemImage: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.chromeMetrics) private var metrics

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: metrics.headerButtonIconSize))
                .foregroundStyle(Color.buoyOnAccent(isProminent: isHovering))
                .frame(width: metrics.headerButtonSize, height: metrics.headerButtonSize)
                .contentShape(Circle())
                .buoyAccentCircle(isHovering: isHovering)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .onHover { isHovering = $0 }
    }
}
