import SwiftUI
import AppKit

/// Single-line text that scrolls horizontally when it is too wide for the space
/// it is given, and sits still when it fits.
///
/// Shared by the Harbor Mode pill and the main header, which show the same note
/// title at the same size in very different amounts of room.
///
/// Under Reduce Motion it renders a static, truncated string: continuous
/// horizontal movement is precisely what that setting exists to stop. Read from
/// the environment rather than `BuoyMotion` so flipping the setting takes effect
/// without a relaunch.
struct MarqueeText: View {
    let text: String
    let font: NSFont
    let color: Color
    /// Width the text has to live in. The caller measures it; this view does not
    /// expand to fill.
    let availableWidth: CGFloat
    /// How the text sits when it *fits* — the pill left-aligns, the header
    /// centres. Overflowing text always starts flush left, because that is where
    /// a scroll has to begin.
    var restingAlignment: Alignment = .leading

    var gap: CGFloat = PanelLayoutMetrics.marqueeGap
    var pointsPerSecond: CGFloat = PanelLayoutMetrics.marqueePointsPerSecond
    var pause: TimeInterval = PanelLayoutMetrics.marqueePause
    var edgeFadeWidth: CGFloat = PanelLayoutMetrics.marqueeEdgeFadeWidth

    @State private var cycleAnchor = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var textWidth: CGFloat {
        PanelLayoutMetrics.textWidth(text, font: font)
    }

    private var overflows: Bool {
        textWidth > availableWidth
    }

    var body: some View {
        Group {
            if overflows && !reduceMotion {
                scrollingText
            } else {
                restingText
            }
        }
        // `fixedSize` inside makes the scrolling copies wider than the lane, so
        // this frame plus the clip is what keeps the view from reporting that
        // width upward and stretching its container.
        .frame(width: max(0, availableWidth), alignment: .leading)
        .clipped()
    }

    /// `fixedSize` keeps the two copies at their natural width so the scroll has
    /// something to travel across.
    private var textLayer: some View {
        Text(text)
            .font(Font(font))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// No `fixedSize` here, so an over-long title ellipsises rather than running
    /// past the lane when the scroll is suppressed.
    private var restingText: some View {
        Text(text)
            .font(Font(font))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: overflows ? .leading : restingAlignment)
    }

    private var scrollingText: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            HStack(spacing: gap) {
                textLayer
                textLayer
            }
            .offset(x: offset(at: context.date))
        }
        .frame(width: availableWidth, alignment: .leading)
        .clipped()
        .mask(MarqueeEdgeFade(width: availableWidth, fadeWidth: edgeFadeWidth))
        .onAppear { cycleAnchor = MarqueeClock.acquire(text) }
        .onDisappear { MarqueeClock.release(text) }
        .onChange(of: text) { _, newText in cycleAnchor = MarqueeClock.restart(newText) }
    }

    /// Holds still for `pause`, scrolls one full copy plus the gap, then wraps —
    /// the second copy has taken the first one's place, so the reset is seamless.
    private func offset(at date: Date) -> CGFloat {
        let travel = textWidth + gap
        guard travel > 0, pointsPerSecond > 0 else { return 0 }

        let speed = Double(pointsPerSecond)
        let cycleDuration = pause + Double(travel) / speed
        let elapsed = date.timeIntervalSince(cycleAnchor)
            .truncatingRemainder(dividingBy: cycleDuration)

        guard elapsed > pause else { return 0 }
        return -CGFloat((elapsed - pause) * speed)
    }
}

/// Shared scroll phase, keyed by the text being scrolled.
///
/// The main header and the Harbor pill are separate views, so each would
/// otherwise start its own cycle — morphing into Harbor Mode mid-scroll would
/// snap the title back to the start and re-run the opening pause. Keying the
/// cycle start on the text means both views compute the same phase and the
/// handoff is seamless.
///
/// Liveness is a retain count, not a timestamp. During the morph both marquees
/// are briefly alive at once — and the incoming view's `onAppear` runs *before*
/// the outgoing one's `onDisappear`, because the removal transition takes
/// ~0.22s — so the count never reaches zero and the cycle survives. A timestamp
/// refreshed only on acquire/release cannot express that: a marquee visible for
/// a while looks arbitrarily old, and the handoff prunes the very entry it is
/// trying to resume.
@MainActor
enum MarqueeClock {
    private struct Cycle {
        let started: Date
        var users: Int
        /// When the last view stopped showing this text; nil while any still is.
        var idleSince: Date?
    }

    private static var cycles: [String: Cycle] = [:]

    /// How long an unused cycle survives. Comfortably covers the ~0.26s morph,
    /// while being short enough that returning to a note later starts cleanly
    /// from the opening pause rather than resuming mid-slide.
    private static let staleAfter: TimeInterval = 1.0

    /// Titles differing only in surrounding whitespace are the same title — the
    /// pill trims for display and the header does not, and they must agree.
    private static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cycle start for `text`, resuming a live or recently-released one.
    static func acquire(_ text: String, now: Date = Date()) -> Date {
        prune(now: now)
        let key = key(text)
        if var existing = cycles[key] {
            existing.users += 1
            existing.idleSince = nil
            cycles[key] = existing
            return existing.started
        }
        cycles[key] = Cycle(started: now, users: 1, idleSince: nil)
        return now
    }

    /// Starts a fresh cycle — the text itself changed, so there is no phase worth
    /// preserving. Keeps the existing retain count: the same views are still on
    /// screen, they are just showing something new.
    static func restart(_ text: String, now: Date = Date()) -> Date {
        let key = key(text)
        let users = max(1, cycles[key]?.users ?? 1)
        cycles[key] = Cycle(started: now, users: users, idleSince: nil)
        return now
    }

    static func release(_ text: String, now: Date = Date()) {
        let key = key(text)
        guard var existing = cycles[key] else { return }
        existing.users = max(0, existing.users - 1)
        existing.idleSince = existing.users == 0 ? now : nil
        cycles[key] = existing
    }

    private static func prune(now: Date) {
        cycles = cycles.filter { _, cycle in
            guard let idleSince = cycle.idleSince else { return true }
            return now.timeIntervalSince(idleSince) < staleAfter
        }
    }
}

/// Softens both ends of the lane so text slides in and out rather than being
/// chopped at a hard edge.
private struct MarqueeEdgeFade: View {
    let width: CGFloat
    let fadeWidth: CGFloat

    var body: some View {
        let fade = min(fadeWidth, width / 3)
        let fraction = width > 0 ? fade / width : 0

        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: fraction),
                .init(color: .black, location: 1 - fraction),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
