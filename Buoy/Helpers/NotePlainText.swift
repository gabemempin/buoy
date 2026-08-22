import AppKit

/// Plain text for a note, decoded from its RTF once and remembered.
///
/// Decoding RTF spins up the whole attributed-string import machinery, and two
/// call sites were doing it on paths that run constantly:
///
/// - the footer's character/word readout re-decoded the current note on *every*
///   `ContentView.body` evaluation — which is every keystroke — and then threw
///   the result away unless the readout happened to be showing a count;
/// - All Notes' search re-decoded *every* note on every keystroke, so the cost
///   scaled with the size of the library.
///
/// Keyed on the note's `updatedAt` as well as its id, so an edit invalidates the
/// entry without any explicit bookkeeping.
///
/// Main-thread only: every caller is a SwiftUI view body, and keeping it
/// single-threaded avoids paying for synchronisation on the hot path.
@MainActor
enum NotePlainText {
    private struct Entry {
        let updatedAt: Int64
        let text: String
    }

    private static var cache: [String: Entry] = [:]

    /// Bounds the cache for very large libraries. Notes are re-decoded on demand,
    /// so dropping everything is correct, just briefly slower.
    private static let capacity = 256

    static func of(_ note: Note) -> String {
        if let entry = cache[note.id], entry.updatedAt == note.updatedAt {
            return entry.text
        }
        let text = decode(note.contentRTF)
        if cache.count >= capacity { cache.removeAll(keepingCapacity: true) }
        cache[note.id] = Entry(updatedAt: note.updatedAt, text: text)
        return text
    }

    /// Object-replacement characters stand in for to-do attachments; they are
    /// noise in a word count and unmatchable in a search.
    private static func decode(_ rtf: Data) -> String {
        guard !rtf.isEmpty,
              let attributed = try? NSAttributedString(
                data: rtf,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              )
        else { return "" }
        return attributed.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    }
}
