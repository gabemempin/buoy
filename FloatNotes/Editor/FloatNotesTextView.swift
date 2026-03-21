import AppKit

// MARK: - App-level shortcut notifications

extension Notification.Name {
    static let floteNewNote         = Notification.Name("FloatNotes2NewNote")
    static let floteDeleteNote      = Notification.Name("FloatNotes2DeleteNote")
    static let floteCopyToClipboard = Notification.Name("FloatNotes2CopyToClipboard")
    static let flotePreviousNote    = Notification.Name("FloatNotes2PreviousNote")
    static let floteNextNote        = Notification.Name("FloatNotes2NextNote")
    static let floteFocusTitle      = Notification.Name("FloatNotes2FocusTitle")
}

// MARK: - Delegate Protocol

protocol FloatNotesTextViewDelegate: AnyObject {
    func textViewDidChange(_ textView: FloatNotesTextView)
    func textViewHeightDidChange(_ height: CGFloat)
    func textViewSelectionDidChange(_ textView: FloatNotesTextView)
    func textViewRequestShowLinkDialog(selectedText: String)
}

// MARK: - FloatNotesTextView

final class FloatNotesTextView: NSTextView {
    weak var floatDelegate: FloatNotesTextViewDelegate?
    var fontSize: CGFloat = 13 {
        didSet {
            guard fontSize != oldValue else { return }
            updateDefaultTypingAttributes()
            resizeExistingText()
            needsDisplay = true
        }
    }

    var placeholderString = "Start typing… (⌘← ⌘→ to navigate notes)"

    private(set) var measuredHeight: CGFloat = 200
    /// Last known non-zero selection — preserved even after the view resigns first responder.
    private(set) var lastKnownSelection: NSRange = NSRange(location: 0, length: 0)
    /// Last known cursor position (may have length 0).
    private(set) var lastKnownCursorPosition: NSRange = NSRange(location: 0, length: 0)

    // MARK: - Init

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        commonInit()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isRichText = true
        allowsUndo = true
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = true
        textContainerInset = NSSize(width: 4, height: 4)
        backgroundColor = .clear
        drawsBackground = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.35)
        ]
        linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        updateDefaultTypingAttributes()
    }

    private func updateDefaultTypingAttributes() {
        typingAttributes = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.textColor
        ]
    }

    /// Re-applies the current fontSize to all existing text, preserving bold/italic traits.
    private func resizeExistingText() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: fullRange) { val, range, _ in
            guard let font = val as? NSFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            let desc = NSFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(traits)
            let newFont = NSFont(descriptor: desc, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            storage.addAttribute(.font, value: newFont, range: range)
        }
        storage.endEditing()
        // Defer content change to avoid modifying @Observable state during SwiftUI render
        DispatchQueue.main.async { [weak self] in
            self?.notifyChange()
        }
    }

    // MARK: - Selection Tracking

    override func setSelectedRange(_ charRange: NSRange) {
        lastKnownCursorPosition = charRange
        if charRange.length > 0 {
            lastKnownSelection = charRange
        }
        super.setSelectedRange(charRange)
    }

    /// When the text view regains first responder (e.g. after a toolbar button click), restore the
    /// last known selection so `selectedRange()` returns the right value inside formatting actions.
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result && lastKnownSelection.length > 0 {
            setSelectedRange(lastKnownSelection)
        }
        return result
    }

    /// Restores first responder and selection highlight after direct textStorage mutation.
    private func refocusWithSelection() {
        window?.makeFirstResponder(self)
        if lastKnownSelection.length > 0 {
            super.setSelectedRange(lastKnownSelection)
        }
    }

    /// Restores first responder and cursor position for bullet/todo.
    private func restoreFirstResponder() {
        guard window?.firstResponder !== self else { return }
        window?.makeFirstResponder(self)
        super.setSelectedRange(lastKnownCursorPosition)
    }

    // MARK: - Placeholder

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let padding = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0)
        let rect = NSRect(
            x: padding + 4,
            y: textContainerInset.height + 2,
            width: bounds.width - padding * 2,
            height: bounds.height
        )
        (placeholderString as NSString).draw(in: rect, withAttributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.placeholderTextColor
        ])
    }

    // MARK: - Key Equivalents (command keys — intercepted before NSTextView default handling)

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Strip numericPad/function flags — arrow keys carry .numericPad which breaks == .command
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .help])

        // ⌘Z / ⌘⇧Z — undo/redo. Must be checked before the pure-command guard so that
        // ⌘⇧Z (which has .shift in mods) is also caught here instead of falling to super.
        if event.keyCode == 6 && mods.contains(.command) {
            if mods.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        }

        guard mods == .command else { return super.performKeyEquivalent(with: event) }

        switch event.keyCode {
        case 0:  // ⌘A — select all
            // selectAll(nil) can silently fail in a non-activating panel; directly set the range instead.
            if let len = textStorage?.length {
                setSelectedRange(NSRange(location: 0, length: len))
            }
            return true
        case 7:  // ⌘X — cut
            cut(nil)
            return true
        case 8:  // ⌘C — copy
            copy(nil)
            return true
        case 9:  // ⌘V — paste
            paste(nil)
            return true
        case 11: // ⌘B — bold
            applyBold()
            return true
        case 34: // ⌘I — italic
            applyItalic()
            return true
        case 32: // ⌘U — underline
            applyUnderline()
            return true
        case 123: // ⌘← — previous note
            NotificationCenter.default.post(name: .flotePreviousNote, object: nil)
            return true
        case 124: // ⌘→ — next note
            NotificationCenter.default.post(name: .floteNextNote, object: nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: - Key Down Handling

    override func keyDown(with event: NSEvent) {
        let chars = event.characters ?? ""
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let onlyCmd = mods == .command

        // ⌘N → new note
        if chars == "n" && onlyCmd {
            NotificationCenter.default.post(name: .floteNewNote, object: nil)
            return
        }

        // ⌘⌫ (Backspace/Delete key = keyCode 51) → delete note
        if event.keyCode == 51 && onlyCmd {
            NotificationCenter.default.post(name: .floteDeleteNote, object: nil)
            return
        }

        // ⌘⏎ → copy to clipboard
        if (chars == "\r" || chars == "\n") && onlyCmd {
            NotificationCenter.default.post(name: .floteCopyToClipboard, object: nil)
            return
        }

        // ⌘K → link dialog
        if chars == "k" && onlyCmd {
            let sel = selectedRange()
            let selected = sel.length > 0 ? (string as NSString).substring(with: sel) : ""
            floatDelegate?.textViewRequestShowLinkDialog(selectedText: selected)
            return
        }

        // Space → check auto-completion prefixes
        if chars == " " {
            if handleAutoComplete() { return }
        }

        // Enter / Return
        if chars == "\r" || chars == "\n" {
            if handleReturn() { return }
        }

        // Backspace on empty list line (no modifiers)
        if event.keyCode == 51 && mods.isEmpty {
            if handleBackspace() { return }
        }

        super.keyDown(with: event)
    }

    // MARK: - Auto-complete

    private func handleAutoComplete() -> Bool {
        guard let storage = textStorage else { return false }
        let sel = selectedRange()
        let pos = sel.location
        guard pos > 0 else { return false }
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: pos, length: 0))
        let lineStart = lineRange.location
        let textOnLine = nsString.substring(with: NSRange(location: lineStart, length: pos - lineStart))

        // `- ` → bullet
        if textOnLine == "-" {
            storage.replaceCharacters(in: NSRange(location: lineStart, length: 1), with: "• ")
            setSelectedRange(NSRange(location: lineStart + 2, length: 0))
            notifyChange()
            return true
        }

        // `[]` → todo
        if textOnLine == "[]" {
            let attachment = TodoAttachment(isChecked: false)
            let atStr = NSMutableAttributedString(attachment: attachment)
            atStr.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize),
                               range: NSRange(location: 0, length: atStr.length))
            // Explicit font on the space — prevents the first typed character from inheriting
            // stale typingAttributes (e.g. a non-system font from a previous RTF round-trip)
            atStr.append(NSAttributedString(string: " ", attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.textColor
            ]))
            storage.replaceCharacters(in: NSRange(location: lineStart, length: 2), with: atStr)
            setSelectedRange(NSRange(location: lineStart + atStr.length, length: 0))
            typingAttributes = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.textColor]
            notifyChange()
            return true
        }

        return false
    }

    // MARK: - Return Key

    private func handleReturn() -> Bool {
        guard let storage = textStorage else { return false }
        let sel = selectedRange()
        let pos = sel.location
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: pos, length: 0))
        let lineStart = lineRange.location
        let lineText = nsString.substring(with: NSRange(location: lineStart, length: pos - lineStart))

        // Bullet line
        if lineText.hasPrefix("• ") {
            let content = String(lineText.dropFirst(2))
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                storage.replaceCharacters(in: NSRange(location: lineStart, length: 2), with: "")
                setSelectedRange(NSRange(location: lineStart, length: 0))
            } else {
                let newLine = NSAttributedString(string: "\n• ", attributes: typingAttributes)
                storage.replaceCharacters(in: sel, with: newLine)
                setSelectedRange(NSRange(location: pos + 3, length: 0))
            }
            notifyChange()
            return true
        }

        // Todo line
        if lineStart < storage.length {
            let attr = storage.attributes(at: lineStart, effectiveRange: nil)
            if attr[.attachment] is TodoAttachment {
                let lineContent = pos > lineStart + 2
                    ? nsString.substring(with: NSRange(location: lineStart + 2, length: pos - lineStart - 2))
                    : ""

                if lineContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    let removeLen = min(2, storage.length - lineStart)
                    storage.replaceCharacters(in: NSRange(location: lineStart, length: removeLen), with: "")
                    setSelectedRange(NSRange(location: lineStart, length: 0))
                } else {
                    let newAttachment = TodoAttachment(isChecked: false)
                    let newAtStr = NSMutableAttributedString(attachment: newAttachment)
                    newAtStr.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize),
                                         range: NSRange(location: 0, length: newAtStr.length))
                    let newLine = NSMutableAttributedString(string: "\n")
                    newLine.append(newAtStr)
                    newLine.append(NSAttributedString(string: " "))
                    storage.replaceCharacters(in: sel, with: newLine)
                    setSelectedRange(NSRange(location: pos + newLine.length, length: 0))
                }
                notifyChange()
                return true
            }
        }

        return false
    }

    // MARK: - Backspace on empty list line

    private func handleBackspace() -> Bool {
        guard let storage = textStorage else { return false }
        let sel = selectedRange()
        guard sel.length == 0 else { return false }
        let pos = sel.location
        guard pos > 0 else { return false }

        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: pos, length: 0))
        let lineStart = lineRange.location
        let lineText = nsString.substring(with: NSRange(location: lineStart, length: pos - lineStart))

        // Bullet: cursor immediately after "• "
        if lineText == "• " {
            storage.replaceCharacters(in: NSRange(location: lineStart, length: 2), with: "")
            setSelectedRange(NSRange(location: lineStart, length: 0))
            notifyChange()
            return true
        }

        // Todo: cursor right after attachment + space
        if lineStart < storage.length {
            let attr = storage.attributes(at: lineStart, effectiveRange: nil)
            if attr[.attachment] is TodoAttachment, pos == lineStart + 2 {
                let removeLen = min(2, storage.length - lineStart)
                storage.replaceCharacters(in: NSRange(location: lineStart, length: removeLen), with: "")
                setSelectedRange(NSRange(location: lineStart, length: 0))
                notifyChange()
                return true
            }
        }

        return false
    }

    // MARK: - Mouse Down (toggle checkboxes)

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let layout = layoutManager, let container = textContainer {
            let glyphIndex = layout.glyphIndex(for: point, in: container,
                                               fractionOfDistanceThroughGlyph: nil)
            if glyphIndex < layout.numberOfGlyphs {
                let charIndex = layout.characterIndexForGlyph(at: glyphIndex)
                if charIndex < textStorage!.length {
                    let attrs = textStorage!.attributes(at: charIndex, effectiveRange: nil)
                    if let todo = attrs[.attachment] as? TodoAttachment {
                        todo.isChecked.toggle()
                        textStorage!.edited(.editedAttributes,
                                           range: NSRange(location: charIndex, length: 1),
                                           changeInLength: 0)
                        notifyChange()
                        return
                    }
                }
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: - Paste

    override func paste(_ sender: Any?) {
        guard let storage = textStorage else { super.paste(sender); return }
        guard let pasted = NSPasteboard.general.string(forType: .string) else {
            // Clipboard has no plain-string type (e.g. HTML-only from Safari).
            // Still normalize after super.paste so foreign colors/fonts are stripped.
            let beforeLoc = selectedRange().location
            super.paste(sender)
            let afterLoc = selectedRange().location
            normalizeFontInRange(NSRange(location: beforeLoc, length: afterLoc - beforeLoc))
            return
        }

        let sel = selectedRange()
        let nsString = string as NSString
        guard sel.location <= nsString.length else { super.paste(sender); return }
        let lineRange = nsString.lineRange(for: NSRange(location: sel.location, length: 0))
        let lineStart = lineRange.location
        let linePrefix = sel.location > lineStart
            ? nsString.substring(with: NSRange(location: lineStart, length: min(2, sel.location - lineStart)))
            : ""
        let isBulletLine = linePrefix.hasPrefix("• ")
        let isTodoLine = lineStart < storage.length
            && (storage.attributes(at: lineStart, effectiveRange: nil)[.attachment] is TodoAttachment)

        if isBulletLine || isTodoLine {
            // Strip bullet/todo prefixes and paste as plain text
            var cleaned = pasted
            if let regex = try? NSRegularExpression(pattern: "^[•☐☑] ") {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
            }
            let insertion = NSAttributedString(string: cleaned, attributes: typingAttributes)
            storage.replaceCharacters(in: sel, with: insertion)
            setSelectedRange(NSRange(location: sel.location + insertion.length, length: 0))
            notifyChange()
        } else {
            // Standard paste, then normalize fonts/colors on the pasted region
            let beforeLoc = sel.location
            super.paste(sender)
            let afterLoc = selectedRange().location
            let pastedRange = NSRange(location: beforeLoc, length: afterLoc - beforeLoc)
            normalizeFontInRange(pastedRange)
        }
    }

    /// Normalizes pasted text: system font (preserving bold/italic), default foreground color
    /// for non-link runs, no background color. Link runs keep their blue/underlined styling.
    private func normalizeFontInRange(_ range: NSRange) {
        guard let storage = textStorage, range.length > 0,
              NSMaxRange(range) <= storage.length else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attrs, attrRange, _ in
            // Normalize font — preserve bold/italic symbolic traits
            let base = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: fontSize)
            let traits = base.fontDescriptor.symbolicTraits
            let desc = NSFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(traits)
            let newFont = NSFont(descriptor: desc, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            storage.addAttribute(.font, value: newFont, range: attrRange)

            // Force foreground to default only for non-link text.
            // Link runs keep their blue color so actual hyperlinks stay visible.
            if attrs[.link] == nil {
                storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: attrRange)
            }

            // Strip any background color that came from the source app
            storage.removeAttribute(.backgroundColor, range: attrRange)
        }
        storage.endEditing()
        notifyChange()
    }

    // MARK: - Formatting Actions

    func applyBold()   { toggleFontTrait(.bold) }
    func applyItalic() { toggleFontTrait(.italic) }

    func applyUnderline() {
        // selectedRange() is valid when we're first responder (ensured by applyEditorFormat in ContentView)
        var sel = selectedRange()
        if sel.length == 0 { sel = lastKnownSelection }
        guard sel.length > 0, let storage = textStorage else { return }
        var allUnderlined = true
        storage.enumerateAttribute(.underlineStyle, in: sel) { val, _, _ in
            if val == nil { allUnderlined = false }
        }
        storage.beginEditing()
        if allUnderlined {
            storage.removeAttribute(.underlineStyle, range: sel)
        } else {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: sel)
        }
        storage.endEditing()
        window?.makeFirstResponder(self)
        super.setSelectedRange(sel)
        notifyChange()
    }

    func applyBullet(_ cursorRange: NSRange? = nil) {
        guard let storage = textStorage else { return }
        let rawSel = cursorRange ?? (lastKnownSelection.length > 0 ? lastKnownSelection : lastKnownCursorPosition)
        // Clamp to valid bounds — cursor may point past end if text was deleted
        let safeLoc = min(rawSel.location, storage.length)
        let sel = NSRange(location: safeLoc, length: min(rawSel.length, storage.length - safeLoc))
        let nsString = string as NSString
        var lineRanges: [NSRange] = []
        let scanRange = sel.length > 0 ? sel : nsString.lineRange(for: sel)
        var pos = scanRange.location
        while pos <= scanRange.location + scanRange.length {
            let lr = nsString.lineRange(for: NSRange(location: pos, length: 0))
            lineRanges.append(lr)
            pos = lr.upperBound
            if pos >= scanRange.location + scanRange.length { break }
        }
        storage.beginEditing()
        var offset = 0
        for lr in lineRanges {
            let adjStart = lr.location + offset
            guard adjStart <= storage.length else { continue }
            let previewLen = min(2, storage.length - adjStart)
            let lineText = (storage.string as NSString).substring(
                with: NSRange(location: adjStart, length: previewLen))
            if lineText.hasPrefix("• ") {
                storage.replaceCharacters(in: NSRange(location: adjStart, length: 2), with: "")
                offset -= 2
            } else if adjStart < storage.length,
                      storage.attributes(at: adjStart, effectiveRange: nil)[.attachment] is TodoAttachment {
                storage.replaceCharacters(in: NSRange(location: adjStart, length: previewLen), with: "• ")
            } else {
                storage.replaceCharacters(in: NSRange(location: adjStart, length: 0), with: "• ")
                offset += 2
            }
        }
        storage.endEditing()
        window?.makeFirstResponder(self)
        notifyChange()
    }

    func applyTodo(_ cursorRange: NSRange? = nil) {
        guard let storage = textStorage else { return }
        let rawSel = cursorRange ?? (lastKnownSelection.length > 0 ? lastKnownSelection : lastKnownCursorPosition)
        // Clamp to valid bounds — cursor may point past end if text was deleted
        let safeLoc = min(rawSel.location, storage.length)
        let safeLen = min(rawSel.length, storage.length - safeLoc)
        let sel = NSRange(location: safeLoc, length: safeLen)
        let nsString = string as NSString

        // Collect all line ranges covered by the selection (mirrors applyBullet logic)
        var lineRanges: [NSRange] = []
        let scanRange = sel.length > 0 ? sel : nsString.lineRange(for: sel)
        var pos = scanRange.location
        while pos <= scanRange.location + scanRange.length {
            let lr = nsString.lineRange(for: NSRange(location: pos, length: 0))
            lineRanges.append(lr)
            pos = lr.upperBound
            if pos >= scanRange.location + scanRange.length { break }
        }

        storage.beginEditing()
        var offset = 0
        for lr in lineRanges {
            let adjStart = lr.location + offset
            guard adjStart <= storage.length else { continue }
            if adjStart < storage.length,
               storage.attributes(at: adjStart, effectiveRange: nil)[.attachment] is TodoAttachment {
                // Already a todo — remove it
                let removeLen = min(2, storage.length - adjStart)
                storage.replaceCharacters(in: NSRange(location: adjStart, length: removeLen), with: "")
                offset -= removeLen
            } else {
                let previewLen = min(2, storage.length - adjStart)
                let lineText = adjStart < storage.length
                    ? (storage.string as NSString).substring(with: NSRange(location: adjStart, length: previewLen))
                    : ""
                let a = TodoAttachment(isChecked: false)
                let aStr = NSMutableAttributedString(attachment: a)
                aStr.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize),
                                  range: NSRange(location: 0, length: aStr.length))
                aStr.append(NSAttributedString(string: " ", attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: NSColor.textColor
                ]))
                if lineText.hasPrefix("• ") {
                    storage.replaceCharacters(in: NSRange(location: adjStart, length: 2), with: aStr)
                    offset += aStr.length - 2
                } else {
                    storage.replaceCharacters(in: NSRange(location: adjStart, length: 0), with: aStr)
                    offset += aStr.length
                }
            }
        }
        storage.endEditing()
        window?.makeFirstResponder(self)
        notifyChange()
    }

    func insertLink(text: String, url: String, at position: NSRange? = nil) {
        guard let storage = textStorage else { return }
        let finalURL = url.hasPrefix("http") ? url : "https://\(url)"
        let display = text.isEmpty ? finalURL : text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .link: URL(string: finalURL) as Any
        ]
        let atStr = NSAttributedString(string: display, attributes: attrs)
        // Use caller-captured position (avoids stale lastKnownSelection overwriting cursor)
        let sel = position ?? (lastKnownSelection.length > 0 ? lastKnownSelection : lastKnownCursorPosition)
        window?.makeFirstResponder(self)
        storage.replaceCharacters(in: sel, with: atStr)
        setSelectedRange(NSRange(location: sel.location + atStr.length, length: 0))
        // Explicitly reset typing attrs so text typed right after the link
        // doesn't inherit blue/underlined/linked formatting.
        typingAttributes = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.textColor
        ]
        notifyChange()
    }

    // MARK: - Height Measurement

    func measureContentHeight() -> CGFloat {
        guard let layout = layoutManager, let container = textContainer else { return 200 }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let chrome = textContainerInset.height * 2
        return max(200, min(700, used.height + chrome + 20))
    }

    // MARK: - Helpers

    private func toggleFontTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        var sel = selectedRange()
        if sel.length == 0 { sel = lastKnownSelection }
        guard sel.length > 0, let storage = textStorage else { return }
        var allHave = true
        storage.enumerateAttribute(.font, in: sel) { val, _, _ in
            guard let f = val as? NSFont else { allHave = false; return }
            if !f.fontDescriptor.symbolicTraits.contains(trait) { allHave = false }
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: sel) { val, range, _ in
            let base = (val as? NSFont) ?? NSFont.systemFont(ofSize: self.fontSize)
            let currentTraits = base.fontDescriptor.symbolicTraits
            let newTraits = allHave ? currentTraits.subtracting(trait) : currentTraits.union(trait)
            let desc = NSFont.systemFont(ofSize: base.pointSize).fontDescriptor.withSymbolicTraits(newTraits)
            let newFont = NSFont(descriptor: desc, size: base.pointSize) ?? base
            storage.addAttribute(.font, value: newFont, range: range)
        }
        storage.endEditing()
        window?.makeFirstResponder(self)
        super.setSelectedRange(sel)
        notifyChange()
    }

    /// After any text edit, normalize typing attributes back to system font.
    /// Prevents Arial/Helvetica corruption after deleting a todo attachment
    /// (RTF round-trip replaces NSFont.systemFont with a named font like Helvetica).
    override func didChangeText() {
        super.didChangeText()
        var attrs = typingAttributes
        if let font = attrs[.font] as? NSFont {
            let sysFont = NSFont.systemFont(ofSize: fontSize)
            let isSystemFont = font.familyName == sysFont.familyName
                || font.familyName?.hasPrefix(".") == true
            if !isSystemFont {
                let traits = font.fontDescriptor.symbolicTraits
                let desc = sysFont.fontDescriptor.withSymbolicTraits(traits)
                attrs[.font] = NSFont(descriptor: desc, size: fontSize) ?? sysFont
                typingAttributes = attrs
            }
        }
    }

    /// Strips link-style typing attributes (blue color, underline, .link URL, pointer cursor)
    /// when the cursor moves to a position that is NOT inside a link.
    ///
    /// The check is based on the character AFTER the cursor: if it exists and is a link we're
    /// still inside one; otherwise we've exited the link and should type in plain style.
    /// (Checking "char after" avoids false-positives when the cursor sits right at the end
    /// of a link — the char *before* the cursor is the link itself, but new text goes after.)
    private func fixTypingAttributesIfOffLink() {
        var attrs = typingAttributes
        // Fast exit — nothing to fix if typing attrs don't have link styling
        let hasLinkColor = (attrs[.foregroundColor] as? NSColor) == NSColor.linkColor
        guard attrs[.link] != nil || hasLinkColor else { return }

        guard let storage = textStorage, storage.length > 0 else {
            // Empty document — strip whatever link attrs are there
            attrs.removeValue(forKey: .link)
            attrs.removeValue(forKey: .cursor)
            attrs.removeValue(forKey: .underlineStyle)
            if hasLinkColor { attrs[.foregroundColor] = NSColor.textColor }
            typingAttributes = attrs
            return
        }

        // Is the character immediately AFTER the cursor part of a link?
        let pos = selectedRange().location
        let charAfterIsLink: Bool
        if pos < storage.length {
            charAfterIsLink = storage.attributes(at: pos, effectiveRange: nil)[.link] != nil
        } else {
            charAfterIsLink = false  // cursor is at end of document
        }

        // Still inside a link — leave typing attrs as-is
        guard !charAfterIsLink else { return }

        // Cursor has exited the link — restore plain typing attributes
        attrs.removeValue(forKey: .link)
        attrs.removeValue(forKey: .cursor)
        attrs.removeValue(forKey: .underlineStyle)
        if (attrs[.foregroundColor] as? NSColor) == NSColor.linkColor {
            attrs[.foregroundColor] = NSColor.textColor
        }
        typingAttributes = attrs
    }

    private func notifyChange() {
        floatDelegate?.textViewDidChange(self)
        let h = measureContentHeight()
        measuredHeight = h
        floatDelegate?.textViewHeightDidChange(h)
        needsDisplay = true // refresh placeholder
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting: Bool) {
        lastKnownCursorPosition = charRange
        if charRange.length > 0 {
            lastKnownSelection = charRange
        }
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting {
            fixTypingAttributesIfOffLink()
            floatDelegate?.textViewSelectionDidChange(self)
        }
    }

    /// NSTextView routes ALL user-driven selection changes (drag, click, shift-click) through
    /// setSelectedRanges (plural), bypassing the singular overrides above. This is the definitive
    /// hook for tracking what the user actually selected.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard let first = ranges.first?.rangeValue else { return }
        lastKnownCursorPosition = first
        if first.length > 0 {
            lastKnownSelection = first
        }
        if !stillSelecting {
            fixTypingAttributesIfOffLink()
            floatDelegate?.textViewSelectionDidChange(self)
        }
    }

    // MARK: - Plain text export

    func plainTextContent() -> String {
        guard let storage = textStorage else { return string }
        var result = ""
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, range, _ in
            if let todo = attrs[.attachment] as? TodoAttachment {
                result += todo.isChecked ? "☑ " : "☐ "
            } else {
                result += (storage.string as NSString).substring(with: range)
            }
        }
        return result
    }

    // MARK: - HTML export (for Apple Notes transfer)

    func htmlContent() -> String {
        guard let storage = textStorage else { return "" }
        let fullRange = NSRange(location: 0, length: storage.length)
        let rawString = storage.string as NSString
        var html = ""
        var inList = false

        // Process line by line to handle bullets and todos as list items
        let lines = rawString.components(separatedBy: "\n")
        var charIndex = 0

        for (lineIndex, line) in lines.enumerated() {
            let lineRange = NSRange(location: charIndex, length: line.utf16.count)
            // Determine if this line starts with a bullet or todo
            var isBullet = false
            var isTodo = false
            var todoChecked = false
            var contentStart = lineRange.location

            // Check for todo attachment at start of line
            if lineRange.length > 0 {
                let firstCharRange = NSRange(location: lineRange.location, length: 1)
                let firstChar = rawString.substring(with: firstCharRange)
                if firstChar == "\u{FFFC}" {
                    // Text attachment — check if it's a todo
                    let attrs = storage.attributes(at: lineRange.location, effectiveRange: nil)
                    if let todo = attrs[.attachment] as? TodoAttachment {
                        isTodo = true
                        todoChecked = todo.isChecked
                        contentStart = lineRange.location + 1
                        // Skip trailing space after checkbox
                        if contentStart < lineRange.location + lineRange.length {
                            let nextChar = rawString.substring(with: NSRange(location: contentStart, length: 1))
                            if nextChar == " " {
                                contentStart += 1
                            }
                        }
                    }
                }
                // Check for bullet character
                if line.hasPrefix("•") || line.hasPrefix("・") {
                    isBullet = true
                    contentStart = lineRange.location + 1
                    // Skip trailing space after bullet
                    if contentStart < lineRange.location + lineRange.length {
                        let nextChar = rawString.substring(with: NSRange(location: contentStart, length: 1))
                        if nextChar == " " {
                            contentStart += 1
                        }
                    }
                }
            }

            let isListItem = isBullet || isTodo
            if isListItem && !inList {
                html += "<ul>"
                inList = true
            } else if !isListItem && inList {
                html += "</ul>"
                inList = false
            }

            let contentLength = lineRange.location + lineRange.length - contentStart
            let contentRange = NSRange(location: contentStart, length: max(0, contentLength))

            if isTodo {
                let checkStr = todoChecked ? "☑ " : "☐ "
                html += "<li>\(checkStr)"
                html += attributedSubstringToHTML(storage: storage, range: contentRange)
                html += "</li>"
            } else if isBullet {
                html += "<li>"
                html += attributedSubstringToHTML(storage: storage, range: contentRange)
                html += "</li>"
            } else {
                html += attributedSubstringToHTML(storage: storage, range: contentRange)
                // Add line break between lines (not after last line)
                if lineIndex < lines.count - 1 {
                    html += "<br>"
                }
            }

            // Advance past the line content + the newline separator
            charIndex += line.utf16.count + 1 // +1 for \n
        }

        if inList {
            html += "</ul>"
        }

        return html
    }

    /// Convert a range of attributed text to HTML, preserving bold/italic/underline/links.
    private func attributedSubstringToHTML(storage: NSTextStorage, range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        var html = ""
        let rawString = storage.string as NSString

        storage.enumerateAttributes(in: range) { attrs, attrRange, _ in
            var text = rawString.substring(with: attrRange)
            // Escape HTML entities
            text = text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")

            // Skip attachment characters (already handled)
            if text == "\u{FFFC}" { return }

            var prefix = ""
            var suffix = ""

            // Check font traits for bold/italic
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) {
                    prefix += "<b>"
                    suffix = "</b>" + suffix
                }
                if traits.contains(.italic) {
                    prefix += "<i>"
                    suffix = "</i>" + suffix
                }
            }

            // Underline
            if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
                prefix += "<u>"
                suffix = "</u>" + suffix
            }

            // Strikethrough
            if let strike = attrs[.strikethroughStyle] as? Int, strike != 0 {
                prefix += "<s>"
                suffix = "</s>" + suffix
            }

            // Link
            if let link = attrs[.link] {
                let urlString: String
                if let url = link as? URL {
                    urlString = url.absoluteString
                } else {
                    urlString = "\(link)"
                }
                let escapedURL = urlString
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "\"", with: "&quot;")
                prefix += "<a href=\"\(escapedURL)\">"
                suffix = "</a>" + suffix
            }

            html += prefix + text + suffix
        }

        return html
    }

    // MARK: - RTF data

    /// Sentinel strings embedded in RTF to represent TodoAttachment checkboxes.
    /// These are converted back to real TodoAttachment objects on load.
    private static let todoUncheckedMarker = "\u{FFFE}TODO_UNCHECKED\u{FFFE}"
    private static let todoCheckedMarker   = "\u{FFFE}TODO_CHECKED\u{FFFE}"

    func rtfContent() -> Data? {
        guard let storage = textStorage else { return nil }
        // Replace TodoAttachment characters with marker strings before RTF serialization,
        // because standard RTF cannot persist custom NSTextAttachment subclasses.
        let copy = NSMutableAttributedString(attributedString: storage)
        var offset = 0
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { val, range, _ in
            guard let todo = val as? TodoAttachment else { return }
            let marker = todo.isChecked ? Self.todoCheckedMarker : Self.todoUncheckedMarker
            let markerAttr = NSAttributedString(string: marker, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.textColor
            ])
            let adjustedRange = NSRange(location: range.location + offset, length: range.length)
            copy.replaceCharacters(in: adjustedRange, with: markerAttr)
            offset += marker.utf16.count - range.length
        }
        return try? copy.data(
            from: NSRange(location: 0, length: copy.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    func loadRTF(_ data: Data) {
        if data.isEmpty {
            textStorage?.setAttributedString(NSAttributedString(string: ""))
            needsDisplay = true
            return
        }
        guard let atStr = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else {
            textStorage?.setAttributedString(NSAttributedString(string: ""))
            needsDisplay = true
            return
        }
        // Normalize fonts AND colors on load so that text stored with foreign colors
        // (e.g. grey from a previous paste before normalization was added) is corrected
        // every time the note is displayed, without needing a re-paste.
        let mutable = NSMutableAttributedString(attributedString: atStr)
        let fullRange = NSRange(location: 0, length: mutable.length)

        mutable.enumerateAttributes(in: fullRange) { attrs, range, _ in
            // Font: normalize to system font, preserving bold/italic symbolic traits
            let base = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: fontSize)
            let traits = base.fontDescriptor.symbolicTraits
            let desc = NSFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(traits)
            mutable.addAttribute(.font,
                                 value: NSFont(descriptor: desc, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize),
                                 range: range)

            // Color: force labelColor for non-link text; links keep their blue.
            if attrs[.link] == nil {
                mutable.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
            }
        }

        // RTF round-trip often loses the font attribute on attachment characters (NSTextAttachment
        // uses U+FFFC). Explicitly set system font on all attachment characters so that deleting
        // them doesn't corrupt the typing attributes with Helvetica/Arial fallback.
        mutable.enumerateAttribute(.attachment, in: fullRange) { val, range, _ in
            guard val != nil else { return }
            mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize), range: range)
        }

        // Restore TodoAttachment markers back to real attachments
        for (marker, checked) in [(Self.todoUncheckedMarker, false), (Self.todoCheckedMarker, true)] {
            while true {
                let searchRange = NSRange(location: 0, length: mutable.length)
                let found = (mutable.string as NSString).range(of: marker, range: searchRange)
                guard found.location != NSNotFound else { break }
                let attachment = TodoAttachment(isChecked: checked)
                let atStr = NSMutableAttributedString(attachment: attachment)
                atStr.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize),
                                   range: NSRange(location: 0, length: atStr.length))
                mutable.replaceCharacters(in: found, with: atStr)
            }
        }

        textStorage?.setAttributedString(mutable)
        needsDisplay = true
    }

    // MARK: - Right-click Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }

        // Remove the system "Layout Orientation" item — not relevant for single-direction notes.
        if let idx = menu.items.firstIndex(where: { $0.title == "Layout Orientation" }) {
            // Remove the separator immediately before it if present
            if idx > 0, menu.items[idx - 1].isSeparatorItem {
                menu.removeItem(at: idx - 1)
            }
            menu.items.removeAll { $0.title == "Layout Orientation" }
        }

        // Inject our formatting options into the system's existing "Transformations" submenu
        // so there is only one submenu, not two.
        if let existingItem = menu.items.first(where: { $0.title == "Transformations" }),
           let sub = existingItem.submenu {
            sub.addItem(.separator())
            let boldItem      = sub.addItem(withTitle: "Bold",      action: #selector(boldAction(_:)),      keyEquivalent: "")
            let italicItem    = sub.addItem(withTitle: "Italic",    action: #selector(italicAction(_:)),    keyEquivalent: "")
            let underlineItem = sub.addItem(withTitle: "Underline", action: #selector(underlineAction(_:)), keyEquivalent: "")
            sub.addItem(.separator())
            let linkItem      = sub.addItem(withTitle: "Link…",     action: #selector(linkAction(_:)),      keyEquivalent: "")
            boldItem.target      = self
            italicItem.target    = self
            underlineItem.target = self
            linkItem.target      = self
        }

        return menu
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(boldAction(_:)) ||
           item.action == #selector(italicAction(_:)) ||
           item.action == #selector(underlineAction(_:)) {
            // Use lastKnownSelection — right-clicking may clear the live selectedRange()
            // but the selection the user made before right-clicking is still in lastKnownSelection.
            return lastKnownSelection.length > 0
        }
        return super.validateMenuItem(item)
    }

    @objc private func boldAction(_ sender: Any?)      { applyBold() }
    @objc private func italicAction(_ sender: Any?)    { applyItalic() }
    @objc private func underlineAction(_ sender: Any?) { applyUnderline() }
    @objc private func linkAction(_ sender: Any?) {
        let sel = selectedRange()
        let selected = sel.length > 0 ? (string as NSString).substring(with: sel) : ""
        floatDelegate?.textViewRequestShowLinkDialog(selectedText: selected)
    }
}
