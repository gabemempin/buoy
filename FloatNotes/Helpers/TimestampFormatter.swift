import Foundation

enum TimestampFormatter {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d h:mm a"
        return f
    }()

    /// Formats a Unix millisecond timestamp for display.
    /// - Same calendar day → "2:34 PM"
    /// - Yesterday → "Yesterday 2:34 PM"
    /// - Older → "Mar 18 2:34 PM"
    static func format(_ unixMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixMs) / 1000)
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return timeFormatter.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "Yesterday \(timeFormatter.string(from: date))"
        } else {
            return dateTimeFormatter.string(from: date)
        }
    }
}
