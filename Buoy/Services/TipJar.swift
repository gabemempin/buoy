import Foundation

/// The tip page behind Settings ▸ General ▸ About ▸ Leave a Tip (Ko-fi,
/// paid out through PayPal: Stripe doesn't take accounts from the
/// Philippines). The amount is chosen on that page, so the app only ever
/// opens the link and never touches payment details.
enum TipJar {
    /// `nil` hides the button. Your Ko-fi page, e.g. `https://ko-fi.com/name`.
    static let url: URL? = URL(string: "https://ko-fi.com/gabemempin")
}
