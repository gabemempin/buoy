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

    /// Only a backstop against entries for deleted notes piling up; an edit
    /// replaces its note's entry rather than adding one. It must stay well
    /// above any real library size. At 256 a search over 500 notes filled the
    /// cache, emptied it and refilled it on every pass, so nothing was ever a
    /// hit and each keystroke decoded ~1,000 RTF blobs (~140ms). The text for
    /// thousands of notes is a few megabytes.
    private static let capacity = 10_000

    static func of(_ note: Note) -> String {
        if let entry = cache[note.id], entry.updatedAt == note.updatedAt {
            return entry.text
        }
        let text = decode(note.contentRTF)
        if cache.count >= capacity { cache.removeAll(keepingCapacity: true) }
        cache[note.id] = Entry(updatedAt: note.updatedAt, text: text)
        return text
    }

    /// Decodes every note the cache is missing off the main thread, so the
    /// first search keystroke after All Notes opens is not the one that pays
    /// for the whole library. RTF import, unlike HTML import, is safe off the
    /// main thread. A note edited meanwhile is stored under its old
    /// `updatedAt`, which simply misses and is decoded again on demand.
    static func prewarm(_ notes: [Note]) {
        let missing = notes.compactMap { note -> (String, Int64, Data)? in
            if let entry = cache[note.id], entry.updatedAt == note.updatedAt { return nil }
            return (note.id, note.updatedAt, note.contentRTF)
        }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) {
            let decoded = missing.map { ($0.0, $0.1, decode($0.2)) }
            await MainActor.run {
                // Only fill gaps: an entry written by `of` in the meantime is
                // at least as fresh as this one.
                for (id, updatedAt, text) in decoded where cache[id] == nil {
                    if cache.count >= capacity { cache.removeAll(keepingCapacity: true) }
                    cache[id] = Entry(updatedAt: updatedAt, text: text)
                }
            }
        }
    }

    /// Object-replacement characters stand in for to-do attachments; they are
    /// noise in a word count and unmatchable in a search.
    nonisolated private static func decode(_ rtf: Data) -> String {
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
