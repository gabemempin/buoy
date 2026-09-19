import SwiftUI
import AppKit

/// A colour the user picked, stored the way the wheel presents it.
///
/// HSL rather than HSB: on an HSL wheel the fully saturated colours sit on the
/// rim at a constant lightness and the centre is white, which is the wheel
/// people recognise. HSB puts white nowhere on the disc and makes the rim
/// change lightness as the hue goes round.
///
/// Not RGB or a hex string, because round-tripping through those moves the
/// handle: many triples map back to a slightly different hue, and a fully
/// desaturated colour has no hue left to recover at all.
struct HSLColor: Codable, Hashable {
    /// 0...1, where 0 is red and the wheel runs clockwise from there.
    var hue: Double
    var saturation: Double
    var lightness: Double

    init(hue: Double, saturation: Double, lightness: Double) {
        self.hue = hue.clampedToUnitRange
        self.saturation = saturation.clampedToUnitRange
        self.lightness = lightness.clampedToUnitRange
    }

    /// Accepts the `brightness` key the HSB version wrote, so a settings file
    /// from before the wheel changed keeps its colours instead of silently
    /// resetting to none.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hue = (try? container.decode(Double.self, forKey: .hue)) ?? 0
        let saturation = (try? container.decode(Double.self, forKey: .saturation)) ?? 0
        let lightness = (try? container.decode(Double.self, forKey: .lightness))
            ?? (try? container.decode(Double.self, forKey: .brightness))
            ?? 0.5
        self.init(hue: hue, saturation: saturation, lightness: lightness)
    }

    private enum CodingKeys: String, CodingKey {
        case hue, saturation, lightness, brightness
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hue, forKey: .hue)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(lightness, forKey: .lightness)
    }

    // MARK: Conversion

    /// HSL to RGB, the standard formulation.
    var rgb: (red: Double, green: Double, blue: Double) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue * 6
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let base = lightness - chroma / 2

        let (r, g, b): (Double, Double, Double)
        switch sector {
        case ..<1:  (r, g, b) = (chroma, second, 0)
        case ..<2:  (r, g, b) = (second, chroma, 0)
        case ..<3:  (r, g, b) = (0, chroma, second)
        case ..<4:  (r, g, b) = (0, second, chroma)
        case ..<5:  (r, g, b) = (second, 0, chroma)
        default:    (r, g, b) = (chroma, 0, second)
        }
        return (r + base, g + base, b + base)
    }

    /// Builds one from any colour, for the system picker's answer.
    init(red: Double, green: Double, blue: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2

        var hue: Double = 0
        if delta > 0 {
            switch maximum {
            case red:   hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            case green: hue = (blue - red) / delta + 2
            default:    hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        let saturation = (delta == 0 || lightness == 0 || lightness == 1)
            ? 0
            : delta / (1 - abs(2 * lightness - 1))
        self.init(hue: hue, saturation: saturation, lightness: lightness)
    }

    var color: Color {
        let c = rgb
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    var nsColor: NSColor {
        let c = rgb
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    /// Perceived lightness, used to decide what colour can legibly sit *on*
    /// this one. The coefficients are the usual Rec. 601 luma weights.
    var luminance: Double {
        let c = rgb
        return 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue
    }

    /// The hue families the picker names back to the user. Nobody wants to read
    /// a hex value out of a colour wheel, but "Teal" is worth knowing.
    var familyName: String {
        guard saturation > 0.08 else { return BuoyWording.gray }
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
