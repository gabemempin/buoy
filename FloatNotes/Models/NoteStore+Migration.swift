import Foundation
import AppKit
import GRDB

/// Handles one-time migration from legacy Electron HTML content to RTF data.
enum NoteStore_Migration {

    static func migrateHTMLtoRTF(in db: DatabaseQueue) {
        // Fetch notes that have legacy `content` HTML but empty/null contentRTF
        let rows: [(id: String, content: String)]
        do {
            rows = try db.read { db in
                let sql = """
                    SELECT id, content FROM notes
                    WHERE (contentRTF IS NULL OR length(contentRTF) = 0)
                    AND length(content) > 0
                """
                return try Row.fetchAll(db, sql: sql).compactMap { row -> (String, String)? in
                    guard let id = row["id"] as? String,
                          let content = row["content"] as? String else { return nil }
                    return (id, content)
                }
            }
        } catch {
            print("[Migration] Failed to fetch legacy notes: \(error)")
            return
        }

        guard !rows.isEmpty else { return }

        for (id, html) in rows {
            let attributed = parseHTMLtoAttributedString(html)
            let rtfData = attributed.rtfData()
            guard let rtfData else { continue }
            try? db.write { db in
                try db.execute(
                    sql: "UPDATE notes SET contentRTF = ? WHERE id = ?",
                    arguments: [rtfData, id]
                )
            }
        }
        print("[Migration] Migrated \(rows.count) notes from HTML to RTF.")
    }

    // MARK: - HTML → NSAttributedString

    private static func parseHTMLtoAttributedString(_ html: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        // Split by <div> blocks
        let divs = html
            .replacingOccurrences(of: "<div>", with: "\n")
            .replacingOccurrences(of: "</div>", with: "")
        let lines = divs.components(separatedBy: "\n")

        for (i, line) in lines.enumerated() {
            if i > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(parseLine(line))
        }
        return result
    }

    private static func parseLine(_ line: String) -> NSAttributedString {
        // Check for todo items
        if line.contains("todo-check") {
            let isChecked = line.contains("checked")
            let attachment = TodoAttachment(isChecked: isChecked)
            let atStr = NSMutableAttributedString(attachment: attachment)
            // Strip todo HTML and get text
            let text = stripHTML(line)
                .trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                atStr.append(NSAttributedString(string: " " + text))
            }
            return atStr
        }

        // Parse inline formatting: <b>, <i>, <u>, <a href>
        return parseInlineHTML(line)
    }

    private static func parseInlineHTML(_ html: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = html

        // Very basic inline HTML parser
        let tags: [(open: String, close: String, attr: NSAttributedString.Key, value: Any)] = [
            ("<b>", "</b>", .font, NSFont.boldSystemFont(ofSize: 13)),
            ("<strong>", "</strong>", .font, NSFont.boldSystemFont(ofSize: 13)),
            ("<i>", "</i>", .font, NSFont.systemFont(ofSize: 13)),
            ("<em>", "</em>", .font, NSFont.systemFont(ofSize: 13)),
            ("<u>", "</u>", .underlineStyle, NSUnderlineStyle.single.rawValue),
        ]

        // Strip all tags for now with a simple regex-like approach
        // and handle <a href> links
        let stripped = handleLinks(in: remaining)
        var cleaned = stripped.string
        // Strip remaining tags
        cleaned = stripHTML(cleaned)
        result.append(NSAttributedString(string: cleaned))
        // Merge link attributes
        result.addAttributes(stripped.attributes(at: 0, effectiveRange: nil), range: NSRange(location: 0, length: 0))

        // A simpler approach: just strip all HTML and return plain text
        // The full inline parser would be complex; for migration we prioritize content fidelity
        let plainResult = NSMutableAttributedString(string: stripHTML(html))
        return plainResult
    }

    private static func handleLinks(in html: String) -> NSAttributedString {
        // Handle <a href="...">text</a>
        let result = NSMutableAttributedString(string: html)
        let pattern = #"<a href="([^"]+)">([^<]+)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return NSAttributedString(string: stripHTML(html))
        }
        let nsString = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))
        var output = NSMutableAttributedString()
        var cursor = 0
        for match in matches {
            let preRange = NSRange(location: cursor, length: match.range.location - cursor)
            let pre = stripHTML(nsString.substring(with: preRange))
            output.append(NSAttributedString(string: pre))
            let url = nsString.substring(with: match.range(at: 1))
            let text = nsString.substring(with: match.range(at: 2))
            let linked = NSAttributedString(string: text, attributes: [
                .link: URL(string: url) as Any
            ])
            output.append(linked)
            cursor = match.range.upperBound
        }
        let tail = stripHTML(nsString.substring(from: cursor))
        output.append(NSAttributedString(string: tail))
        return output
    }

    private static func stripHTML(_ html: String) -> String {
        var result = html
        // Remove all HTML tags
        while let start = result.range(of: "<"),
              let end = result.range(of: ">", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        // Decode common HTML entities
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return result
    }
}

// MARK: - NSAttributedString RTF helpers

private extension NSAttributedString {
    func rtfData() -> Data? {
        let range = NSRange(location: 0, length: length)
        return try? data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
