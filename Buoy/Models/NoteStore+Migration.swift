import Foundation
import AppKit
import GRDB

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

    private static func parseHTMLtoAttributedString(_ html: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = html
            .replacingOccurrences(of: "<div>", with: "\n")
            .replacingOccurrences(of: "</div>", with: "")
            .components(separatedBy: "\n")

        for (i, line) in lines.enumerated() {
            if i > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(parseLine(line))
        }
        return result
    }

    private static func parseLine(_ line: String) -> NSAttributedString {
        if line.contains("todo-check") {
            let attachment = TodoAttachment(isChecked: line.contains("checked"))
            let atStr = NSMutableAttributedString(attachment: attachment)
            let text = stripHTML(line).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { atStr.append(NSAttributedString(string: " " + text)) }
            return atStr
        }
        return NSMutableAttributedString(string: stripHTML(line))
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
