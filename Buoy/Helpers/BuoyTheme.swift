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
    var accentChoice: HSBColor?
    var tintChoice: HSBColor?
    var tintIntensity: Double

    static let system = BuoyTheme(accentChoice: nil, tintChoice: nil, tintIntensity: 0)

    init(accentChoice: HSBColor?, tintChoice: HSBColor?, tintIntensity: Double) {
        self.accentChoice = accentChoice
        self.tintChoice = tintChoice
        self.tintIntensity = tintIntensity.clampedToUnitRange
    }

    init(settings: AppSettings) {
        self.init(
            accentChoice: settings.accentColor,
            tintChoice: settings.windowTint,
            tintIntensity: settings.windowTintIntensity
        )
    }

    // MARK: Accent

    var accentNSColor: NSColor { accentChoice?.nsColor ?? .controlAccentColor }
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

    // MARK: Tint

    var tint: Color? { tintChoice?.color }

    /// How strongly the tint shows through the glass. Kept deliberately low:
    /// the panel is a backdrop for text, and the readable ceiling is a long way
    /// below "coloured".
    var tintOpacity: Double {
        guard tintChoice != nil else { return 0 }
        return 0.06 + tintIntensity * 0.30
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

@available(macOS 26, *)
extension BuoyTheme {
    /// Liquid Glass, tinted when the user has chosen a window colour.
    ///
    /// `.regular` untinted is the default and stays pixel-identical to what
    /// shipped before the tint existed, so nobody who never opens the colour
    /// picker sees their panel change.
    func glassStyle() -> Glass {
        guard let tint else { return .regular }
        return .regular.tint(tint.opacity(tintOpacity))
    }
}
