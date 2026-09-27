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

    var accentNSColor: NSColor {
        // No clamp. The accent is whatever was picked, everywhere it is used.
        // There used to be a legible-lightness band here, which meant the
        // colour on screen was not quite the colour in the picker.
        accentChoice?.nsColor ?? .controlAccentColor
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
        guard let accentChoice else { return .alternateSelectedControlTextColor }
        return accentChoice.luminance > 0.62
            ? NSColor(white: 0.12, alpha: 1)
            : NSColor(white: 1, alpha: 1)
    }

    var onAccent: Color { Color(nsColor: onAccentNSColor) }

    /// The accent as *text*, deepened or lifted when it cannot be read on the
    /// panel — but never moved off its own hue.
    ///
    /// The accent is used exactly as chosen whenever it stands apart from the
    /// panel, either in luminance or by sitting far enough round the hue wheel
    /// from the tint that the hue carries it. A yellow title on a blue panel
    /// has almost no luminance contrast and is perfectly legible, so nothing
    /// happens to it.
    ///
    /// Only when neither holds does it move, and then only along lightness.
    /// Hue and saturation are never touched, so a purple accent gives a deep
    /// purple title that still matches the buttons. Borrowing the *tint's* hue
    /// was tried and is worse: it matched the panel and not the accent, so a
    /// purple app got a navy title.
    func accentText(isDark: Bool) -> NSColor {
        guard let accentChoice else {
            return isDark ? .white : .controlAccentColor
        }
        let background = Self.luminance(panelBackground(isDark: isDark))

        if Self.contrast(accentChoice.luminance, background) >= Self.minimumTitleContrast {
            return accentChoice.nsColor
        }
        if let tintChoice,
           Self.hueDistance(accentChoice.hue, tintChoice.hue) >= Self.distinctHueDistance {
            return accentChoice.nsColor
        }
        return Self.readable(accentChoice, against: background).nsColor
    }

    /// Base and glint for the Bug Report title shimmer.
    ///
    /// The base is the accent as text, except that the system accent stays
    /// the accent in dark mode too rather than turning white: the shimmer is
    /// meant to read as colour. The glint is the base's complementary hue at
    /// full brightness. A near-grey accent has no meaningful complement, so it
    /// falls back to the original gold.
    func bugReportShimmer(isDark: Bool) -> (base: NSColor, highlight: NSColor) {
        let base = accentChoice == nil ? NSColor.controlAccentColor : accentText(isDark: isDark)
        guard let rgb = base.usingColorSpace(.sRGB), rgb.saturationComponent >= 0.15 else {
            return (base, NSColor(srgbRed: 1, green: 0.85, blue: 0, alpha: 1))
        }
        let hue = (rgb.hueComponent + 0.5).truncatingRemainder(dividingBy: 1)
        let highlight = NSColor(
            hue: hue,
            saturation: max(rgb.saturationComponent, 0.75),
            brightness: 1,
            alpha: 1
        )
        return (base, highlight)
    }

    /// Walks lightness both ways and takes whichever reaches the target first,
    /// or gets closest.
    ///
    /// Trying only one direction is what produced the bad results before: a
    /// colour sitting almost exactly on the background's luminance can be
    /// pushed either way, and guessing from which side it happens to fall on
    /// turned a bright yellow white one time and muddy the next.
    private static func readable(_ color: HSLColor, against background: Double) -> HSLColor {
        var best = color
        var bestContrast = contrast(color.luminance, background)
        var bestDistance = Double.greatestFiniteMagnitude

        for step in [0.03, -0.03] {
            var lightness = color.lightness
            var moved: Double = 0
            while lightness > 0.05, lightness < 0.95 {
                lightness += step
                moved += 0.03
                let candidate = HSLColor(
                    hue: color.hue,
                    saturation: color.saturation,
                    lightness: lightness
                )
                let value = contrast(candidate.luminance, background)
                if value >= minimumTitleContrast {
                    if moved < bestDistance {
                        best = candidate
                        bestContrast = value
                        bestDistance = moved
                    }
                    break
                }
                if bestDistance == .greatestFiniteMagnitude, value > bestContrast {
                    best = candidate
                    bestContrast = value
                }
            }
        }
        return best
    }

    /// Deliberately short of the 4.5 a body-text guideline would ask for. The
    /// title is large and semibold, and the point is to catch a collision, not
    /// to restyle every accent that is merely close.
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
