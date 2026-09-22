import AppKit

/// Markdown task markers become native checklists in Notes' macOS 26 importer.
enum NoteMarkdown {
    static func export(_ content: NSAttributedString, title: String, indentWidth: CGFloat) -> String {
        var result = "# \(escape(title.components(separatedBy: .newlines).joined(separator: " ")))\n\n"
        let text = content.string as NSString
        var location = 0
        var previousWasList = false

        while location < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            var end = NSMaxRange(paragraph)
            while end > location,
                  CharacterSet.newlines.contains(UnicodeScalar(text.character(at: end - 1)) ?? " ") {
                end -= 1
            }
            var start = location
            var marker = ""
            if let todo = content.attribute(.attachment, at: start, effectiveRange: nil) as? TodoAttachment {
                marker = todo.isChecked ? "- [x] " : "- [ ] "
                start += 1
            } else if text.substring(with: NSRange(location: start, length: end - start)).hasPrefix("• ") {
                marker = "- "
                start += 1
            }
            let isList = !marker.isEmpty
            if isList, start < end, text.character(at: start) == 32 { start += 1 }
            if location > 0, isList != previousWasList { result += "\n" }
            if isList,
               let style = content.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle {
                let level = max(0, Int((style.firstLineHeadIndent / indentWidth).rounded()))
                result += String(repeating: "    ", count: level)
            }
            result += marker + inline(content.attributedSubstring(from: NSRange(location: start, length: end - start)))
            // A hard break preserves separate non-list lines in Markdown.
            result += isList || start == end ? "\n" : "  \n"
            previousWasList = isList
            location = NSMaxRange(paragraph)
        }
        return result
    }

    private static func inline(_ content: NSAttributedString) -> String {
        var result = ""
        content.enumerateAttributes(in: NSRange(location: 0, length: content.length)) { attributes, range, _ in
            let raw = (content.string as NSString).substring(with: range)
            let core = raw.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { result += raw; return }
            let leading = String(raw.prefix(while: { $0.isWhitespace }))
            let trailing = String(raw.reversed().prefix(while: { $0.isWhitespace }).reversed())
            var rendered = escape(core)
            if let font = attributes[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                if traits.contains(.italicFontMask) { rendered = "*\(rendered)*" }
                if traits.contains(.boldFontMask) { rendered = "**\(rendered)**" }
            }
            if let strike = attributes[.strikethroughStyle] as? NSNumber, strike.intValue != 0 {
                rendered = "~~\(rendered)~~"
            }
            if let link = attributes[.link] {
                let destination = (link as? URL)?.absoluteString ?? (link as? String ?? "")
                if !destination.isEmpty {
                    let escaped = destination.replacingOccurrences(of: "\\", with: "%5C")
                        .replacingOccurrences(of: " ", with: "%20")
                        .replacingOccurrences(of: "<", with: "%3C")
                        .replacingOccurrences(of: ">", with: "%3E")
                        .replacingOccurrences(of: "\n", with: "%0A")
                        .replacingOccurrences(of: "\r", with: "%0D")
                    rendered = "[\(rendered)](<\(escaped)>)"
                }
            }
            result += leading + rendered + trailing
        }
        return result
    }

    private static func escape(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            if "\\`*_{}[]<>()#+-.!|~".contains(character) { result.append("\\") }
            result.append(character)
        }
    }
}
