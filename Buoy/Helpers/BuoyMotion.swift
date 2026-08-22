import AppKit
import SwiftUI

/// Central Reduce Motion gate.
///
/// System Settings ▸ Accessibility ▸ Display ▸ Reduce Motion asks apps to drop
/// *movement* — slides, springs, scaling, marquees, window morphs — and either
/// substitute a plain crossfade or make the change instantly. The preference is
/// not a global animation kill switch: opacity fades are still fine and are
/// left alone throughout Buoy.
///
/// Every animation that moves or resizes something routes through here rather
/// than reading the preference at the call site, so there is one place to audit
/// and one place to change the substitution policy.
///
/// SwiftUI views that render continuously (the Harbor pill marquee, the bug
/// report title shimmer) read `@Environment(\.accessibilityReduceMotion)`
/// instead, because that value re-invalidates the body when the user flips the
/// setting mid-session; the statics here are read at the moment an animation
/// starts, which is already current.
enum BuoyMotion {
    /// Whether the user has asked for reduced motion.
    private static var isReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Tempo of the crossfade substituted in place of a movement animation.
    /// Short enough to read as a state change rather than an effect.
    private static let crossfadeDuration: TimeInterval = 0.12

    // MARK: - SwiftUI animations

    /// Substitutes a crossfade for `animation` when Reduce Motion is on.
    private static func animation(
        _ animation: Animation,
        fallbackDuration: TimeInterval = crossfadeDuration
    ) -> Animation {
        isReduced ? .easeInOut(duration: fallbackDuration) : animation
    }

    static func easeOut(_ duration: TimeInterval) -> Animation {
        animation(.easeOut(duration: duration), fallbackDuration: min(duration, crossfadeDuration))
    }

    static func easeIn(_ duration: TimeInterval) -> Animation {
        animation(.easeIn(duration: duration), fallbackDuration: min(duration, crossfadeDuration))
    }

    static func easeInOut(_ duration: TimeInterval) -> Animation {
        animation(.easeInOut(duration: duration), fallbackDuration: min(duration, crossfadeDuration))
    }

    /// Springs overshoot by definition, so they always collapse to a crossfade.
    static func spring(response: Double, dampingFraction: Double) -> Animation {
        animation(.spring(response: response, dampingFraction: dampingFraction))
    }

    // MARK: - SwiftUI transitions

    /// Strips the movement/scale component from a transition, leaving the fade.
    static func transition(_ transition: AnyTransition) -> AnyTransition {
        isReduced ? .opacity : transition
    }

    // MARK: - AppKit

    /// Collapses an `NSAnimationContext` duration to an instant change.
    ///
    /// Window frame animations have no meaningful crossfade equivalent — the
    /// panel either travels or it doesn't — so under Reduce Motion the frame is
    /// simply set. Completion handlers still run, which matters for the Harbor
    /// Mode generation guards in `AppDelegate`.
    static func duration(_ duration: TimeInterval) -> TimeInterval {
        isReduced ? 0 : duration
    }
}
