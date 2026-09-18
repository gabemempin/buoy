import Foundation

/// American spelling unless the user's Mac is set to a variety of English that
/// uses the British one.
///
/// Buoy's own source comments are written in British English; its *interface*
/// should not force that on someone whose Mac is set to US English. Only the
/// handful of words that actually differ live here — there is no point routing
/// every string through a lookup.
enum BuoyWording {
    static let usesBritishSpelling: Bool = {
        let identifier = Locale.preferredLanguages.first ?? Locale.current.identifier
        let locale = Locale(identifier: identifier)
        guard locale.language.languageCode?.identifier == "en" else { return false }
        // The region can come from the language tag (en-GB) or, for someone
        // running plain "en", from the Region setting underneath it.
        let region = locale.language.region?.identifier ?? Locale.current.region?.identifier
        guard let region else { return false }
        return ["GB", "AU", "NZ", "IE", "ZA", "IN"].contains(region)
    }()

    private static func pick(_ american: String, _ british: String) -> String {
        usesBritishSpelling ? british : american
    }

    static var color: String { pick("Color", "Colour") }
    static var colorLowercased: String { pick("color", "colour") }
    static var colors: String { pick("Colors", "Colours") }
    static var behavior: String { pick("Behavior", "Behaviour") }
    static var gray: String { pick("Gray", "Grey") }
}
