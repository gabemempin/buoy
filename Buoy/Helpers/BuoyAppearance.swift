import AppKit
import SwiftUI

// MARK: - Increase Contrast

/// System Settings ▸ Accessibility ▸ Display ▸ Increase Contrast.
///
/// Buoy's chrome is built from low-opacity fills and hairline strokes over
/// glass, which is exactly the vocabulary that setting exists to strengthen.
/// Rather than sprinkle `if increaseContrast` through the views, the semantic
/// colors below read this and darken themselves.
enum BuoyContrast {
    static var isIncreased: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    /// Raises an opacity toward opaque when Increase Contrast is on, leaving it
    /// untouched otherwise. `boosted` is the value used under the setting.
    static func opacity(_ standard: Double, boosted: Double) -> Double {
        isIncreased ? boosted : standard
    }
}

// MARK: - Semantic colors

extension Color {
    /// Foreground for content drawn on top of an accent-filled control.
    ///
    /// Buoy used a literal `.white` here, which is only correct while the accent
    /// color happens to be dark. With no custom accent set this is AppKit's own
    /// matching foreground for a selected control, which tracks the system
    /// accent, the Graphite appearance and Increase Contrast. With one set it
    /// is derived from that colour's luminance instead — see
    /// `BuoyTheme.onAccentNSColor` for why AppKit's answer goes wrong there.
    ///
    /// Reads `BuoyTheme.current` rather than the environment because it is a
    /// static on `Color` and has none. Same caveat as the tokens below: it
    /// resolves at body evaluation, so a change applies on the next render.
    /// Every settings write re-renders the panel, so that is immediate here.
    static var buoyOnAccent: Color {
        BuoyTheme.current.onAccent
    }

    /// Same, dimmed for a resting (non-hovered) control. Kept as one place so the
    /// resting/hover pair stays legible under Increase Contrast, where the dim
    /// state is pushed back to full strength.
    static func buoyOnAccent(isProminent: Bool) -> Color {
        buoyOnAccent.opacity(isProminent ? 1 : BuoyContrast.opacity(0.85, boosted: 1))
    }

    /// Hairline divider inside accent-filled capsules and pill groups.
    static var buoyOnAccentSeparator: Color {
        buoyOnAccent.opacity(BuoyContrast.opacity(0.3, boosted: 0.7))
    }

    /// Neutral fill behind small circular glyph buttons in overlay panels.
    static var buoyControlFill: Color {
        Color.primary.opacity(BuoyContrast.opacity(0.08, boosted: 0.2))
    }

    /// Selected-row / active-item wash in list-style overlays.
    static var buoySelectionFill: Color {
        Color.primary.opacity(BuoyContrast.opacity(0.08, boosted: 0.18))
    }

    /// Hairline border around floating overlay surfaces.
    static var buoyOverlayStroke: Color {
        Color.primary.opacity(BuoyContrast.opacity(0.08, boosted: 0.35))
    }

    /// Outline for a low-emphasis capsule button.
    static var buoyOutlineStroke: Color {
        Color.primary.opacity(BuoyContrast.opacity(0.25, boosted: 0.6))
    }

    /// Track behind the segmented theme picker.
    static var buoySegmentTrack: Color {
        Color.primary.opacity(BuoyContrast.opacity(0.07, boosted: 0.16))
    }

    /// Selected segment in the theme picker.
    static var buoySegmentSelection: Color {
        Color.primary.opacity(BuoyContrast.opacity(0.15, boosted: 0.32))
    }
}

// MARK: - Typography

/// Buoy's text scale, expressed in macOS semantic text styles.
///
/// The chrome previously carried ~80 raw `\.system(size:)` literals, which meant
/// none of it tracked system text metrics and every size was an independent
/// guess. Each role below resolves to the AppKit text style that already renders
/// at that size, so the rendered result is unchanged today while the app now
/// follows the system's ladder rather than a private one.
///
/// Deliberately covers *text* only. SF Symbol sizing stays as explicit point
/// sizes at the call site: those are icon metrics, not type, and text styles are
/// the wrong control for them.
enum BuoyFont {
    /// 13pt semibold — dialog headline.
    static let headline = Font.headline
    /// 12pt — control labels, settings rows, list rows.
    static let control = Font.callout
    /// 12pt semibold — overlay panel titles.
    static let sectionTitle = Font.callout.weight(.semibold)
    /// 11pt — secondary labels, button text inside capsules.
    static let secondary = Font.subheadline
    /// 11pt medium — emphasised secondary labels.
    static let secondaryEmphasized = Font.subheadline.weight(.medium)
    /// 11pt semibold — primary action button text.
    static let secondaryProminent = Font.subheadline.weight(.semibold)
    /// 10pt — footer metadata, key-cap glyphs.
    static let caption = Font.caption
}
