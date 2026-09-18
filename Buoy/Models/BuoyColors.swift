import SwiftUI
import AppKit

/// A colour the user picked, stored the way the wheel thinks about it.
///
/// HSB rather than RGB or a hex string because the picker is a hue/saturation
/// wheel: round-tripping through RGB would quietly move the handle, since many
/// RGB triples map back to a slightly different hue and a fully desaturated
/// colour has no hue at all to recover.
struct HSBColor: Codable, Hashable {
    /// 0...1, where 0 is red and the wheel runs clockwise from there.
    var hue: Double
    var saturation: Double
    var brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue.clampedToUnitRange
        self.saturation = saturation.clampedToUnitRange
        self.brightness = brightness.clampedToUnitRange
    }

    var color: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    var nsColor: NSColor {
        NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    /// Perceived lightness, used to decide what colour can legibly sit *on* this
    /// one. The coefficients are the usual Rec. 601 luma weights.
    var luminance: Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        // sRGB first: `getRed` traps on a colour in any other space, and an
        // HSB-constructed NSColor is not guaranteed to be in one already.
        let rgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)
    }

    /// The nine hue families the picker names back to the user. Nobody wants to
    /// read a hex value out of a colour wheel, but "Teal" is worth knowing.
    var familyName: String {
        guard saturation > 0.08 else { return "Grey" }
        switch hue * 360 {
        case ..<15, 345...:  return "Red"
        case ..<45:          return "Orange"
        case ..<70:          return "Yellow"
        case ..<160:         return "Green"
        case ..<195:         return "Teal"
        case ..<240:         return "Blue"
        case ..<280:         return "Indigo"
        case ..<320:         return "Purple"
        default:             return "Pink"
        }
    }
}

extension Double {
    var clampedToUnitRange: Double { Swift.min(1, Swift.max(0, self)) }
}
