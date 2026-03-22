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

    /// Dedicated undo manager — bypasses the responder chain so undo always works
    /// regardless of whether NSHostingView breaks the chain to the panel-level manager.
    private let _localUndoManager = UndoManager()
    override var undoManager: UndoManager? { _localUndoManager }

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
        typingAttributes = normalizedTypingAttributes()
    }

    /// Returns a safe attribute set for inserted plain text.
    /// This keeps checklist pastes on the app's system font, adaptive color, and line spacing
    /// while preserving paragraph-level settings from the surrounding text when available.
    private func normalizedTypingAttributes(
        basedOn source: [NSAttributedString.Key: Any]? = nil
    ) -> [NSAttributedString.Key: Any] {
        let sysFont = NSFont.systemFont(ofSize: fontSize)
        let style = ((source?[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        style.lineSpacing = 3

        let traits = (source?[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        let desc = sysFont.fontDescriptor.withSymbolicTraits(traits)
        let font = NSFont(descriptor: desc, size: fontSize) ?? sysFont

        var attrs = source ?? [:]
        attrs[.font] = font
        attrs[.foregroundColor] = NSColor.textColor
        attrs[.paragraphStyle] = style
        attrs.removeValue(forKey: .backgroundColor)
        return attrs
    }

    private func normalizedPlainTextAttributes(at location: Int) -> [NSAttributedString.Key: Any] {
        guard let storage = textStorage, storage.length > 0 else {
            return normalizedTypingAttributes()
        }

        let clampedLocation = min(max(location, 0), storage.length)
        if clampedLocation < storage.length {
            return normalizedTypingAttributes(basedOn: storage.attributes(at: clampedLocation, effectiveRange: nil))
        }
        if clampedLocation > 0 {
            return normalizedTypingAttributes(basedOn: storage.attributes(at: clampedLocation - 1, effectiveRange: nil))
        }
        return normalizedTypingAttributes()
    }

    @discardableResult
    private func replaceText(in range: NSRange, with replacement: NSAttributedString) -> Bool {
        guard let storage = textStorage else { return false }
        guard shouldChangeText(in: range, replacementString: replacement.string) else { return false }
        storage.replaceCharacters(in: range, with: replacement)
        didChangeText()
        return true
    }

    @discardableResult
    private func replaceText(in range: NSRange, with replacement: String) -> Bool {
        replaceText(in: range, with: NSAttributedString(string: replacement, attributes: typingAttributes))
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
        // Strip noise flags — numericPad/function/help on arrow keys, capsLock always
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .help, .capsLock])

        // ⌘⇧Z — redo (must check before the .command-only guard below)
        if mods == [.command, .shift] && event.keyCode == 6 {
            undoManager?.redo()
            return true
        }

        guard mods == .command else { return super.performKeyEquivalent(with: event) }

        // Use charactersIgnoringModifiers for locale-independent key matching
        let ch = event.charactersIgnoringModifiers ?? ""

        switch ch {
        case "a":  // ⌘A — select all
            selectAll(nil)
            return true
        case "z":  // ⌘Z — undo
            undoManager?.undo()
            return true
        case "c":  // ⌘C — copy (handle directly so it works in non-activating panel)
            copy(nil)
            return true
        case "v":  // ⌘V — paste
            paste(nil)
            return true
        case "x":  // ⌘X — cut
            cut(nil)
            return true
        case "b":  // ⌘B — bold
            applyBold()
            return true
        case "i":  // ⌘I — italic
            applyItalic()
            return true
        case "u":  // ⌘U — underline
            applyUnderline()
            return true
        default:
            break
        }

        // Arrow key navigation (keyCodes are hardware-position-based, reliable for arrows)
        switch event.keyCode {
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
            guard replaceText(in: NSRange(location: lineStart, length: 1), with: "• ") else { return false }
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
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            atStr.append(NSAttributedString(string: " ", attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: style
            ]))
            guard replaceText(in: NSRange(location: lineStart, length: 2), with: atStr) else { return false }
            setSelectedRange(NSRange(location: lineStart + atStr.length, length: 0))
            updateDefaultTypingAttributes()
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
                guard replaceText(in: NSRange(location: lineStart, length: 2), with: "") else { return false }
                setSelectedRange(NSRange(location: lineStart, length: 0))
            } else {
                let newLine = NSAttributedString(string: "\n• ", attributes: typingAttributes)
                guard replaceText(in: sel, with: newLine) else { return false }
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
                    guard replaceText(in: NSRange(location: lineStart, length: removeLen), with: "") else { return false }
                    setSelectedRange(NSRange(location: lineStart, length: 0))
                } else {
                    let newAttachment = TodoAttachment(isChecked: false)
                    let newAtStr = NSMutableAttributedString(attachment: newAttachment)
                    newAtStr.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize),
                                         range: NSRange(location: 0, length: newAtStr.length))
                    let newLine = NSMutableAttributedString(string: "\n")
                    newLine.append(newAtStr)
                    newLine.append(NSAttributedString(string: " "))
                    guard replaceText(in: sel, with: newLine) else { return false }
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
            guard replaceText(in: NSRange(location: lineStart, length: 2), with: "") else { return false }
            setSelectedRange(NSRange(location: lineStart, length: 0))
            notifyChange()
            return true
        }

        // Todo: cursor right after attachment + space
        if lineStart < storage.length {
            let attr = storage.attributes(at: lineStart, effectiveRange: nil)
            if attr[.attachment] is TodoAttachment, pos == lineStart + 2 {
                let removeLen = min(2, storage.length - lineStart)
                guard replaceText(in: NSRange(location: lineStart, length: removeLen), with: "") else { return false }
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
            super.paste(sender)
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
            let insertionAttributes = normalizedPlainTextAttributes(at: sel.location)
            let insertion = NSAttributedString(string: cleaned, attributes: insertionAttributes)
            guard replaceText(in: sel, with: insertion) else { return }
            setSelectedRange(NSRange(location: sel.location + insertion.length, length: 0))
            typingAttributes = insertionAttributes
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

    /// Normalizes fonts in the given range to system font (preserving bold/italic traits)
    /// and strips foreign colors/backgrounds.
    private func normalizeFontInRange(_ range: NSRange) {
        guard let storage = textStorage, range.length > 0,
              NSMaxRange(range) <= storage.length else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { val, attrRange, _ in
            guard let font = val as? NSFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            let desc = NSFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(traits)
            let newFont = NSFont(descriptor: desc, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            storage.addAttribute(.font, value: newFont, range: attrRange)
        }
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
        storage.removeAttribute(.backgroundColor, range: range)
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
        guard shouldChangeText(in: sel, replacementString: nil) else { return }
        storage.beginEditing()
        if allUnderlined {
            storage.removeAttribute(.underlineStyle, range: sel)
        } else {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: sel)
        }
        storage.endEditing()
        didChangeText()
        window?.makeFirstResponder(self)
        super.setSelectedRange(sel)
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
            // Skip lines that are empty (only a newline character or nothing)
            let origLineText = nsString.substring(with: lr).trimmingCharacters(in: .whitespacesAndNewlines)
            if origLineText.isEmpty { continue }

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
            // Skip lines that are empty (only a newline character or nothing)
            let origLineText = nsString.substring(with: lr).trimmingCharacters(in: .whitespacesAndNewlines)
            if origLineText.isEmpty { continue }

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
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 3
                aStr.append(NSAttributedString(string: " ", attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: NSColor.textColor,
                    .paragraphStyle: style
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
        guard shouldChangeText(in: sel, replacementString: atStr.string) else { return }
        storage.replaceCharacters(in: sel, with: atStr)
        setSelectedRange(NSRange(location: sel.location + atStr.length, length: 0))
        didChangeText()
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

    /// Toggles a font trait (bold/italic) on the current selection.
    /// If there is no selection, toggles the trait for future typing via typingAttributes only —
    /// this prevents accidentally bolding text on a different line.
    private func toggleFontTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        let sel = selectedRange()
        guard sel.length > 0, let storage = textStorage else {
            // No selection — toggle for future typing only (don't touch existing text)
            var attrs = typingAttributes
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                let newTraits = traits.contains(trait) ? traits.subtracting(trait) : traits.union(trait)
                let desc = NSFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(newTraits)
                attrs[.font] = NSFont(descriptor: desc, size: fontSize) ?? font
                typingAttributes = attrs
            }
            return
        }
        var allHave = true
        storage.enumerateAttribute(.font, in: sel) { val, _, _ in
            guard let f = val as? NSFont else { allHave = false; return }
            if !f.fontDescriptor.symbolicTraits.contains(trait) { allHave = false }
        }
        guard shouldChangeText(in: sel, replacementString: nil) else { return }
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
        didChangeText()
        window?.makeFirstResponder(self)
        super.setSelectedRange(sel)
    }

    /// After any text edit, normalize typing attributes back to system font.
    /// Prevents Arial/Helvetica corruption after deleting a todo attachment
    /// (RTF round-trip replaces NSFont.systemFont with a named font like Helvetica).
    override func didChangeText() {
        super.didChangeText()
        typingAttributes = normalizedTypingAttributes(basedOn: typingAttributes)
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
        guard let storage = textStorage else { return plainTextContent() }

        // Build a copy with TodoAttachments replaced by ☐/☑ Unicode chars for HTML export
        let mutable = NSMutableAttributedString(attributedString:
            storage.attributedSubstring(from: NSRange(location: 0, length: storage.length)))

        var attachments: [(NSRange, Bool)] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { val, range, _ in
            if let todo = val as? TodoAttachment {
                attachments.append((range, todo.isChecked))
            }
        }
        for (range, isChecked) in attachments.reversed() {
            let symbol = isChecked ? "☑" : "☐"
            let replacement = NSAttributedString(string: symbol, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.textColor
            ])
            mutable.replaceCharacters(in: range, with: replacement)
        }

        let documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let data = try? mutable.data(
            from: NSRange(location: 0, length: mutable.length),
            documentAttributes: documentAttributes
        ), let html = String(data: data, encoding: .utf8) {
            return html
        }
        return plainTextContent()
    }

    // MARK: - RTF data
    // TodoAttachments are serialized as ☐ (U+2610) / ☑ (U+2611) Unicode characters so that
    // the checked state survives the RTF round-trip. On load, these markers are restored back
    // to TodoAttachment instances.

    func rtfContent() -> Data? {
        guard let storage = textStorage else { return nil }

        // Build a copy with TodoAttachments replaced by ☐/☑ so the state persists in RTF
        let mutable = NSMutableAttributedString(attributedString:
            storage.attributedSubstring(from: NSRange(location: 0, length: storage.length)))

        var attachments: [(NSRange, Bool)] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { val, range, _ in
            if let todo = val as? TodoAttachment {
                attachments.append((range, todo.isChecked))
            }
        }
        // Replace backward to avoid index shifting
        for (range, isChecked) in attachments.reversed() {
            let marker = isChecked ? "\u{2611}" : "\u{2610}" // ☑ or ☐
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            let replacement = NSAttributedString(string: marker, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: style
            ])
            mutable.replaceCharacters(in: range, with: replacement)
        }

        return try? mutable.data(
            from: NSRange(location: 0, length: mutable.length),
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
        // Normalize all fonts to system font, preserving bold/italic traits
        let mutable = NSMutableAttributedString(attributedString: atStr)
        mutable.enumerateAttribute(.font, in: NSRange(location: 0, length: mutable.length)) { val, range, _ in
            guard let font = val as? NSFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            let desc = NSFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(traits)
            let newFont = NSFont(descriptor: desc, size: fontSize)
            mutable.addAttribute(.font, value: newFont ?? NSFont.systemFont(ofSize: fontSize), range: range)
        }
        // Normalize all foreground colors to adaptive labelColor (RTF stores fixed colors).
        // Re-apply link color to link ranges so hyperlinks remain styled.
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.removeAttribute(.foregroundColor, range: fullRange)
        mutable.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
        mutable.enumerateAttribute(.link, in: fullRange) { val, range, _ in
            if val != nil {
                mutable.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
            }
        }
        // Apply consistent line spacing while preserving other paragraph attributes
        var styleUpdates: [(NSRange, NSMutableParagraphStyle)] = []
        mutable.enumerateAttribute(.paragraphStyle, in: fullRange) { val, range, _ in
            let style = ((val as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            style.lineSpacing = 3
            styleUpdates.append((range, style))
        }
        for (range, style) in styleUpdates {
            mutable.addAttribute(.paragraphStyle, value: style, range: range)
        }
        // RTF round-trip often loses the font attribute on attachment characters (NSTextAttachment
        // uses U+FFFC). Explicitly set system font on all attachment characters.
        mutable.enumerateAttribute(.attachment, in: fullRange) { val, range, _ in
            guard val != nil else { return }
            mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize), range: range)
        }
        // Restore TodoAttachments from ☐/☑ markers written by rtfContent()
        for (marker, isChecked) in [("\u{2611}", true), ("\u{2610}", false)] as [(String, Bool)] {
            var searchRange = NSRange(location: 0, length: mutable.length)
            while searchRange.location < mutable.length {
                let found = (mutable.string as NSString).range(of: marker, options: [], range: searchRange)
                if found.location == NSNotFound { break }
                let attachment = TodoAttachment(isChecked: isChecked)
                let atStr = NSMutableAttributedString(attachment: attachment)
                atStr.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize),
                                   range: NSRange(location: 0, length: atStr.length))
                mutable.replaceCharacters(in: found, with: atStr)
                let nextLoc = found.location + atStr.length
                searchRange = NSRange(location: nextLoc, length: mutable.length - nextLoc)
            }
        }
        textStorage?.setAttributedString(mutable)
        updateDefaultTypingAttributes()
        needsDisplay = true
    }

    // MARK: - Right-click Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }

        // Remove writing direction / layout orientation item using action selectors
        // (locale-independent — title strings differ across macOS versions and languages).
        // The standard actions are makeBaseWritingDirectionNatural: / changeLayoutOrientation:
        for item in menu.items where itemIsWritingDirectionOrLayoutOrientation(item) {
            menu.removeItem(item)
        }

        // Find the existing Transformations submenu by checking for the standard
        // uppercaseWord: action inside it (also locale-independent).
        var transformationsItem: NSMenuItem?
        for item in menu.items {
            if let sub = item.submenu,
               sub.items.contains(where: { $0.action == #selector(NSResponder.uppercaseWord(_:)) }) {
                transformationsItem = item
                break
            }
        }

        // If not found, create a new Transformations submenu
        if transformationsItem == nil {
            let sub = NSMenu(title: "Transformations")
            let parent = NSMenuItem(title: "Transformations", action: nil, keyEquivalent: "")
            parent.submenu = sub
            menu.addItem(.separator())
            menu.addItem(parent)
            transformationsItem = parent
        }

        guard let sub = transformationsItem?.submenu else { return menu }

        // Append our formatting items to the Transformations submenu
        sub.addItem(.separator())
        let boldItem      = sub.addItem(withTitle: "Bold",      action: #selector(boldAction(_:)),      keyEquivalent: "")
        let italicItem    = sub.addItem(withTitle: "Italic",    action: #selector(italicAction(_:)),    keyEquivalent: "")
        let underlineItem = sub.addItem(withTitle: "Underline", action: #selector(underlineAction(_:)), keyEquivalent: "")
        sub.addItem(.separator())
        let linkItem = sub.addItem(withTitle: "Link…", action: #selector(linkAction(_:)), keyEquivalent: "")

        boldItem.target      = self
        italicItem.target    = self
        underlineItem.target = self
        linkItem.target      = self

        return menu
    }

    /// Returns true if the menu item represents the writing direction or layout orientation
    /// submenu — identified by the standard NSResponder action selectors it contains.
    private func itemIsWritingDirectionOrLayoutOrientation(_ item: NSMenuItem) -> Bool {
        guard let sub = item.submenu else { return false }
        let writingDirectionActions: [Selector] = [
            #selector(NSResponder.makeBaseWritingDirectionNatural(_:)),
            #selector(NSResponder.makeBaseWritingDirectionLeftToRight(_:)),
            #selector(NSResponder.makeBaseWritingDirectionRightToLeft(_:))
        ]
        return sub.items.contains { writingDirectionActions.contains($0.action ?? Selector("")) }
            || sub.items.contains { $0.action == Selector(("changeLayoutOrientation:")) }
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(boldAction(_:)) ||
           item.action == #selector(italicAction(_:)) ||
           item.action == #selector(underlineAction(_:)) {
            return selectedRange().length > 0
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
