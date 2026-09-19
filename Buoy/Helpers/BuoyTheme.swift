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
    /// Symmetric about the middle on purpose. An earlier 0.28...0.62 was
    /// picked by eye, and because it left more room below mid-lightness than
    /// above, the two shaded bands on the wheel came out visibly different
    /// sizes — which reads as a mistake rather than a rule.
    static let legibleAccentLightness: ClosedRange<Double> = 0.30...0.70

    var accentNSColor: NSColor {
        guard let accentChoice else { return .controlAccentColor }
        return clampedAccent(accentChoice).nsColor
    }

    var accent: Color { Color(nsColor: accentNSColor) }

    /// What can legibly sit *on* an accent fill.
    ///
    /// Cannot be `NSColor.alternateSelectedControlTextColor`: that tracks the
    /// *system* accent, so the moment a user picks an accent of different
    /// lightness it is wrong on every filled control at once — the toolbar
    /// capsule, every circle button, the Harbor restore chevron, the checked
    /// to-do glyph. Derived from the accent's own luminance instead.
    var onAccentNSColor: NSColor {
        guard accentChoice != nil else { return .alternateSelectedControlTextColor }
        return accentLuminance > 0.62
            ? NSColor(white: 0.12, alpha: 1)
            : NSColor(white: 1, alpha: 1)
    }

    var onAccent: Color { Color(nsColor: onAccentNSColor) }

    /// Luminance of the accent as it is actually drawn, clamp included.
    private var accentLuminance: Double {
        guard let accentChoice else { return 0 }
        return clampedAccent(accentChoice).luminance
    }

    /// The accent as *text*, kept readable against whatever the panel is
    /// tinted.
    ///
    /// Three attempts at this, and the first two are why the rule is shaped
    /// the way it is. Forcing a fixed lightness made every accent arrive at
    /// the same brightness whatever its hue: bright yellow buttons, olive
    /// title. Using the accent untouched left a green title invisible on a
    /// green panel. A hue-aware colour distance — the obvious middle
    /// ground — called green-on-yellow "different enough", which it is for a
    /// filled shape and is not for 19pt letterforms.
    ///
    /// So the test is luminance contrast, the thing type actually needs. What
    /// keeps it from flattening every hue is the *direction*: the title moves
    /// away from the panel on the side it is already on. A yellow accent on a
    /// blue panel is the lighter of the two, so it gets lighter still and
    /// stays yellow; a green accent on a pale panel is the darker, so it
    /// deepens. Hue and saturation are never touched.
    func accentText(isDark: Bool) -> NSColor {
        guard let accentChoice else {
            return isDark ? .white : .controlAccentColor
        }
        let accent = clampedAccent(accentChoice)
        let background = Self.luminance(panelBackground(isDark: isDark))
        guard Self.contrast(accent.luminance, background) < Self.minimumTitleContrast else {
            return accent.nsColor
        }
        // Close in lightness is only a problem when the two are also close in
        // hue. A yellow title on a blue panel has little luminance contrast and
        // is perfectly readable, because the hue carries it; a green title on a
        // yellow-green one has the same numbers and is not. Adjusting on
        // luminance alone turned that yellow white.
        if let tintChoice, Self.hueDistance(accent.hue, tintChoice.hue) >= Self.distinctHueDistance {
            return accent.nsColor
        }

        let step: Double = accent.luminance >= background ? 0.03 : -0.03
        var lightness = accent.lightness
        var best = accent
        // Past the legible clamp if it has to be: that band is about a fill
        // holding its own against the panel, and a title that cannot be read
        // is the worse failure of the two.
        for _ in 0..<30 {
            lightness += step
            guard lightness > 0.05, lightness < 0.95 else { break }
            best = HSLColor(hue: accent.hue, saturation: accent.saturation, lightness: lightness)
            if Self.contrast(best.luminance, background) >= Self.minimumTitleContrast {
                break
            }
        }
        return best.nsColor
    }

    /// Deliberately short of the 4.5 a body-text guideline would ask for. The
    /// title is large and semibold, and the point here is to stop a collision,
    /// not to repaint every accent that is merely close.
    private static let minimumTitleContrast: Double = 2.0

    /// Far enough apart on the wheel to stand on hue alone: a quarter turn.
    private static let distinctHueDistance: Double = 0.25

    /// Shortest way round the wheel, 0 to 0.5.
    private static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(raw, 1 - raw)
    }

    private static func contrast(_ a: Double, _ b: Double) -> Double {
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ rgb: (red: Double, green: Double, blue: Double)) -> Double {
        0.299 * rgb.red + 0.587 * rgb.green + 0.114 * rgb.blue
    }

    /// Roughly what the panel looks like behind the title: its appearance,
    /// washed with the tint at the strength the tint is drawn.
    private func panelBackground(isDark: Bool) -> (red: Double, green: Double, blue: Double) {
        let base: Double = isDark ? 0.16 : 0.92
        guard let tintChoice else { return (base, base, base) }
        let tint = tintChoice.rgb
        let alpha = tintOpacity
        return (
            base * (1 - alpha) + tint.red * alpha,
            base * (1 - alpha) + tint.green * alpha,
            base * (1 - alpha) + tint.blue * alpha
        )
    }

    /// The accent with its lightness held inside the legible band — what the
    /// fills are actually drawn in.
    private func clampedAccent(_ choice: HSLColor) -> HSLColor {
        HSLColor(
            hue: choice.hue,
            saturation: choice.saturation,
            lightness: min(
                max(choice.lightness, Self.legibleAccentLightness.lowerBound),
                Self.legibleAccentLightness.upperBound
            )
        )
    }

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
