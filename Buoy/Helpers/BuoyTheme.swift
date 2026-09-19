import SwiftUI
import AppKit

/// The colours the app is currently drawing itself in, resolved once from
/// settings so nothing has to reason about "custom or system?" at the call site.
///
/// Two separate choices feed it. The **accent** replaces the macOS accent on
/// every control Buoy fills — buttons, the toolbar and footer capsules, text
/// selection, checked to-dos. The **tint** is a wash over the panel's glass; it
/// is independent of Light/Dark, so the same hue reads pale on a light panel
/// and deep on a dark one rather than deciding the appearance for you.
struct BuoyTheme: Equatable {
    var accentChoice: HSLColor?
    var tintChoice: HSLColor?
    var tintOpacityFraction: Double

    static let system = BuoyTheme(accentChoice: nil, tintChoice: nil, tintOpacityFraction: 0)

    init(accentChoice: HSLColor?, tintChoice: HSLColor?, tintOpacityFraction: Double) {
        self.accentChoice = accentChoice
        self.tintChoice = tintChoice
        self.tintOpacityFraction = tintOpacityFraction.clampedToUnitRange
    }

    init(settings: AppSettings) {
        self.init(
            accentChoice: settings.accentColor,
            tintChoice: settings.windowTint,
            tintOpacityFraction: settings.windowTintOpacity
        )
    }

    // MARK: Accent

    /// The lightness an accent has to stay within to be usable.
    ///
    /// The accent is a *fill* — buttons, the toolbar capsule, the footer
    /// pill — so what matters is its contrast against the panel behind it, not
    /// against the glyph on top. A near-white accent on light glass leaves a
    /// button that is only visible as the shadow under it, whatever colour the
    /// glyph flips to.
    static let legibleAccentLightness: ClosedRange<Double> = 0.28...0.62

    var accentNSColor: NSColor {
        guard let accentChoice else { return .controlAccentColor }
        return HSLColor(
            hue: accentChoice.hue,
            saturation: accentChoice.saturation,
            lightness: min(
                max(accentChoice.lightness, Self.legibleAccentLightness.lowerBound),
                Self.legibleAccentLightness.upperBound
            )
        ).nsColor
    }

    var accent: Color { Color(nsColor: accentNSColor) }

    /// The accent as *text*, on the panel's own background.
    ///
    /// The note title is drawn in the accent, and a fill that reads well as a
    /// 28pt circle is often too pale as 19pt letterforms. This darkens it in
    /// light mode and lifts it in dark, so the title stays the accent without
    /// becoming something you have to lean in to read.
    func accentText(isDark: Bool) -> NSColor {
        guard let accentChoice else {
            return isDark ? .white : .controlAccentColor
        }
        let target: Double = isDark ? 0.68 : 0.40
        return HSLColor(
            hue: accentChoice.hue,
            saturation: accentChoice.saturation,
            lightness: target
        ).nsColor
    }

    /// What can legibly sit *on* an accent fill.
    ///
    /// Cannot be `NSColor.alternateSelectedControlTextColor`: that tracks the
    /// *system* accent, so the moment a user picks an accent of different
    /// lightness it is wrong on every filled control at once — the toolbar
    /// capsule, every circle button, the Harbor restore chevron, the checked
    /// to-do glyph. Derived from the accent's own luminance instead.
    var onAccentNSColor: NSColor {
        guard let accentChoice else { return .alternateSelectedControlTextColor }
        return accentChoice.luminance > 0.62
            ? NSColor(white: 0.12, alpha: 1)
            : NSColor(white: 1, alpha: 1)
    }

    var onAccent: Color { Color(nsColor: onAccentNSColor) }

    // MARK: Tint

    var tint: Color? { tintChoice?.color }

    /// How strongly the tint shows through the glass. Kept deliberately low:
    /// the panel is a backdrop for text, and the readable ceiling is a long way
    /// below "coloured".
    var tintOpacity: Double {
        guard tintChoice != nil else { return 0 }
        return 0.06 + tintOpacityFraction * 0.30
    }

    /// The same wash on an opaque surface, where there is no blur to soften it.
    var opaqueTintOpacity: Double {
        guard tintChoice != nil else { return 0 }
        return tintOpacity * 0.5
    }

    // MARK: AppKit bridge

    /// The live theme, for the AppKit code that cannot read the SwiftUI
    /// environment: the text view's selection colour, the to-do checkbox image,
    /// the list reorder indicator, the corner resize arcs. Updated by
    /// `AppDelegate.handleSettingsUpdate` alongside everything else.
    static private(set) var current: BuoyTheme = .system

    static func setCurrent(_ theme: BuoyTheme) {
        guard theme != current else { return }
        current = theme
        NotificationCenter.default.post(name: .buoyThemeDidChange, object: nil)
    }
}

extension Notification.Name {
    /// Posted when the accent or tint changes, for AppKit views that have to
    /// redraw themselves rather than being re-rendered by SwiftUI.
    static let buoyThemeDidChange = Notification.Name("BuoyThemeDidChange")
}

private struct BuoyThemeKey: EnvironmentKey {
    static let defaultValue: BuoyTheme = .system
}

extension EnvironmentValues {
    var buoyTheme: BuoyTheme {
        get { self[BuoyThemeKey.self] }
        set { self[BuoyThemeKey.self] = newValue }
    }
}
