import AppKit

/// Links from one note to another, typed with `>>` (see
/// `BuoyTextView.presentNoteLinkMenu`). Stored as an ordinary `.link`
/// attribute with a `buoy://note/<id>` URL, so they survive the RTF round
/// trip, copy and undo like any web link, and only a click tells them apart.
enum NoteLink {
    static let scheme = "buoy"
    static let host = "note"
    /// How many recent notes `>>` offers.
    static let suggestionLimit = 3

    static func url(for noteID: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + noteID
        return components.url
    }

    static func noteID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == host else { return nil }
        let id = url.lastPathComponent
        return id.isEmpty || id == "/" ? nil : id
    }

    /// The click hands the target to `ContentView` through here, because the
    /// notification router's routes take no payload.
    private static var pendingNoteID: String?

    static func open(noteID: String) {
        pendingNoteID = noteID
        NotificationCenter.default.post(name: .buoyOpenNoteLink, object: nil)
    }

    static func takePendingNoteID() -> String? {
        defer { pendingNoteID = nil }
        return pendingNoteID
    }
}

/// One row of the `>>` menu.
struct NoteLinkSuggestion {
    let noteID: String
    let title: String
}

extension Notification.Name {
    static let buoyOpenNoteLink = Notification.Name("BuoyOpenNoteLink")
}
