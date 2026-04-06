import AppKit

// MARK: - App-level shortcut notifications

extension Notification.Name {
    static let buoyNewNote         = Notification.Name("BuoyNewNote")
    static let buoyDeleteNote      = Notification.Name("BuoyDeleteNote")
    static let buoyCopyToClipboard = Notification.Name("BuoyCopyToClipboard")
    static let buoyPreviousNote    = Notification.Name("BuoyPreviousNote")
    static let buoyNextNote        = Notification.Name("BuoyNextNote")
    static let buoyFocusTitle      = Notification.Name("BuoyFocusTitle")
    static let buoyPanelBecameKey  = Notification.Name("BuoyPanelBecameKey")
}

// MARK: - Delegate Protocol

protocol BuoyTextViewDelegate: AnyObject {
    func textViewDidChange(_ textView: BuoyTextView)
    func textViewHeightDidChange(_ height: CGFloat)
    func textViewSelectionDidChange(_ textView: BuoyTextView)
    func textViewRequestShowLinkDialog(selectedText: String)
}

// MARK: - BuoyTextView

final class BuoyTextView: NSTextView {
    private enum EditorSpacing {
        static let line: CGFloat = 4
        static let paragraph: CGFloat = 0
        static let todoParagraph: CGFloat = 4
    }

    private enum ListIndent {
        static let width: CGFloat = 20
        static let maxNestingLevel = 2
    }

    weak var buoyDelegate: BuoyTextViewDelegate?

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

    private func paragraphStyle(
        basedOn source: NSParagraphStyle? = nil,
        isTodoParagraph: Bool = false
    ) -> NSMutableParagraphStyle {
        let style = (source?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.lineSpacing = EditorSpacing.line
        style.paragraphSpacing = isTodoParagraph ? EditorSpacing.todoParagraph : EditorSpacing.paragraph
        return style
    }

    private func todoAttachmentAttributedString(isChecked: Bool = false, indentLevel: Int = 0) -> NSMutableAttributedString {
        let indent = CGFloat(indentLevel) * ListIndent.width
        let para = paragraphStyle(isTodoParagraph: true)
        para.headIndent = indent
        para.firstLineHeadIndent = indent

        let attachment = TodoAttachment(isChecked: isChecked)
        let atStr = NSMutableAttributedString(attachment: attachment)
        atStr.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize),
                           range: NSRange(location: 0, length: atStr.length))
        atStr.addAttribute(.paragraphStyle, value: para,
                           range: NSRange(location: 0, length: atStr.length))
        let spacer = NSAttributedString(string: " ", attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: para
        ])
        atStr.append(spacer)
        return atStr
    }

    private func normalizedTypingAttributes(
        basedOn source: [NSAttributedString.Key: Any]? = nil
    ) -> [NSAttributedString.Key: Any] {
        let sysFont = NSFont.systemFont(ofSize: fontSize)
        let style = paragraphStyle(basedOn: source?[.paragraphStyle] as? NSParagraphStyle)

        let traits = (source?[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        let desc = sysFont.fontDescriptor.withSymbolicTraits(traits)
        let font = NSFont(descriptor: desc, size: fontSize) ?? sysFont

        var attrs = source ?? [:]
        attrs[.font] = font
        attrs[.foregroundColor] = NSColor.textColor
        attrs[.paragraphStyle] = style
        attrs.removeValue(forKey: .attachment)
        attrs.removeValue(forKey: .backgroundColor)
        attrs.removeValue(forKey: .link)
        return attrs
    }

    private func normalizedTypingAttributesForEscapedList(
        basedOn source: [NSAttributedString.Key: Any]? = nil
    ) -> [NSAttributedString.Key: Any] {
        var attrs = normalizedTypingAttributes(basedOn: source ?? typingAttributes)
        let style = paragraphStyle(basedOn: attrs[.paragraphStyle] as? NSParagraphStyle)
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        attrs[.paragraphStyle] = style
        return attrs
    }

    private func normalizedPlainTextAttributes(at location: Int) -> [NSAttributedString.Key: Any] {
        guard let storage = textStorage, storage.length > 0 else {
            return normalizedTypingAttributes()
        }
        let loc = min(max(location, 0), storage.length)
        if loc < storage.length {
            return normalizedTypingAttributes(basedOn: storage.attributes(at: loc, effectiveRange: nil))
        }
        if loc > 0 {
            return normalizedTypingAttributes(basedOn: storage.attributes(at: loc - 1, effectiveRange: nil))
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

    // MARK: - Placeholder

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let padding = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0)
        let rect = NSRect(
            x: padding,
            y: textContainerInset.height,
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

        let ch = event.charactersIgnoringModifiers ?? ""

        switch ch {
        case "a":  selectAll(nil);      return true
        case "z":  undoManager?.undo(); return true
        case "c":  copy(nil);           return true
        case "v":  paste(nil);          return true
        case "x":  cut(nil);            return true
        case "b":  applyBold();         return true
        case "i":  applyItalic();       return true
        case "u":  applyUnderline();    return true
        default:   break
        }

        switch event.keyCode {
        case 123: // ⌘←
            NotificationCenter.default.post(name: .buoyPreviousNote, object: nil)
            return true
        case 124: // ⌘→
            NotificationCenter.default.post(name: .buoyNextNote, object: nil)
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

        if chars == "n" && onlyCmd {
            NotificationCenter.default.post(name: .buoyNewNote, object: nil)
            return
        }

        if event.keyCode == 51 && onlyCmd {
            NotificationCenter.default.post(name: .buoyDeleteNote, object: nil)
            return
        }

        if (chars == "\r" || chars == "\n") && onlyCmd {
            NotificationCenter.default.post(name: .buoyCopyToClipboard, object: nil)
            return
        }

        if chars == "k" && onlyCmd {
            let sel = selectedRange()
            let selected = sel.length > 0 ? (string as NSString).substring(with: sel) : ""
            buoyDelegate?.textViewRequestShowLinkDialog(selectedText: selected)
            return
        }

        if chars == " " && handleAutoComplete() { return }

        if (chars == "\r" || chars == "\n") && handleReturn() { return }

        if event.keyCode == 51 && mods.isEmpty && handleBackspace() { return }

        // Tab / Shift+Tab — indent/outdent list items
        if event.keyCode == 48 {
            if mods.isEmpty && handleTab(isShift: false) { return }
            if mods == .shift && handleTab(isShift: true) { return }
        }

        super.keyDown(with: event)
    }

    // MARK: - Auto-complete

    private func handleAutoComplete() -> Bool {
        let sel = selectedRange()
        let pos = sel.location
        guard pos > 0 else { return false }
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: pos, length: 0))
        let lineStart = lineRange.location
        let textOnLine = nsString.substring(with: NSRange(location: lineStart, length: pos - lineStart))

        if textOnLine == "-" {
            guard replaceText(in: NSRange(location: lineStart, length: 1), with: "• ") else { return false }
            setSelectedRange(NSRange(location: lineStart + 2, length: 0))
            notifyChange()
            return true
        }

        if textOnLine == "[]" {
            // Explicit font on the space prevents the first typed character from inheriting
            // stale typingAttributes after an RTF round-trip.
            let atStr = todoAttachmentAttributedString()
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

        if lineText.hasPrefix("• ") || lineText.hasPrefix("◦ ") {
            let marker = lineText.hasPrefix("◦ ") ? "◦" : "•"
            let content = String(lineText.dropFirst(2))
            let currentLevel = indentLevel(at: lineStart)
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                guard replaceText(in: NSRange(location: lineStart, length: 2), with: "") else { return false }
                // Only reset indent if lineStart still points inside the document after removal.
                // If lineStart == storage.length the characters were at the end and are now gone;
                // calling resetParagraphIndent would clip to the previous paragraph's \n and
                // incorrectly strip its indentation.
                if currentLevel > 0 && lineStart < storage.length {
                    resetParagraphIndent(at: lineStart)
                }
                setSelectedRange(NSRange(location: lineStart, length: 0))
                // Reset typingAttributes so subsequent typing doesn't inherit the nested indent.
                typingAttributes = normalizedTypingAttributesForEscapedList()
            } else {
                let indent = CGFloat(currentLevel) * ListIndent.width
                let newPara = paragraphStyle()
                newPara.headIndent = indent
                newPara.firstLineHeadIndent = indent
                var newAttrs = normalizedTypingAttributes(basedOn: typingAttributes)
                newAttrs[.paragraphStyle] = newPara
                let newLine = NSAttributedString(string: "\n\(marker) ", attributes: newAttrs)
                guard replaceText(in: sel, with: newLine) else { return false }
                setSelectedRange(NSRange(location: pos + newLine.length, length: 0))
            }
            notifyChange()
            return true
        }

        if lineStart < storage.length,
           storage.attributes(at: lineStart, effectiveRange: nil)[.attachment] is TodoAttachment {
            let lineContent = pos > lineStart + 2
                ? nsString.substring(with: NSRange(location: lineStart + 2, length: pos - lineStart - 2))
                : ""
            let currentLevel = indentLevel(at: lineStart)

            if lineContent.trimmingCharacters(in: .whitespaces).isEmpty {
                let removeLen = min(2, storage.length - lineStart)
                guard replaceText(in: NSRange(location: lineStart, length: removeLen), with: "") else { return false }
                if currentLevel > 0 && lineStart < storage.length {
                    resetParagraphIndent(at: lineStart)
                }
                setSelectedRange(NSRange(location: lineStart, length: 0))
                typingAttributes = normalizedTypingAttributesForEscapedList()
            } else {
                let newLine = NSMutableAttributedString(string: "\n")
                newLine.append(todoAttachmentAttributedString(indentLevel: currentLevel))
                guard replaceText(in: sel, with: newLine) else { return false }
                setSelectedRange(NSRange(location: pos + newLine.length, length: 0))
            }
            notifyChange()
            return true
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

        if lineText == "• " {
            guard replaceText(in: NSRange(location: lineStart, length: 2), with: "") else { return false }
            setSelectedRange(NSRange(location: lineStart, length: 0))
            notifyChange()
            return true
        }

        if lineText == "◦ " {
            guard replaceText(in: NSRange(location: lineStart, length: 2), with: "") else { return false }
            resetParagraphIndent(at: lineStart)
            setSelectedRange(NSRange(location: lineStart, length: 0))
            typingAttributes = normalizedTypingAttributesForEscapedList()
            notifyChange()
            return true
        }

        if lineStart < storage.length,
           storage.attributes(at: lineStart, effectiveRange: nil)[.attachment] is TodoAttachment,
           pos == lineStart + 2 {
            let removeLen = min(2, storage.length - lineStart)
            guard replaceText(in: NSRange(location: lineStart, length: removeLen), with: "") else { return false }
            resetParagraphIndent(at: lineStart)
            setSelectedRange(NSRange(location: lineStart, length: 0))
            typingAttributes = normalizedTypingAttributesForEscapedList()
            notifyChange()
            return true
        }

        return false
    }

    // MARK: - Tab / Indent

    private func indentLevel(at lineStart: Int) -> Int {
        guard let storage = textStorage, lineStart < storage.length else { return 0 }
        let style = storage.attribute(.paragraphStyle, at: lineStart, effectiveRange: nil) as? NSParagraphStyle
        return Int((style?.headIndent ?? 0) / ListIndent.width)
    }

    private func resetParagraphIndent(at location: Int) {
        guard let storage = textStorage, storage.length > 0 else { return }
        // When a list marker is removed at end-of-document, the original lineStart can now equal
        // storage.length. Resetting at that clamped location would target the previous paragraph's
        // trailing newline and strip the indent from the line above.
        guard location >= 0, location < storage.length else { return }
        let paraRange = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        guard shouldChangeText(in: paraRange, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: paraRange) { val, range, _ in
            let style = self.paragraphStyle(basedOn: val as? NSParagraphStyle)
            style.headIndent = 0
            style.firstLineHeadIndent = 0
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        }
        storage.endEditing()
        didChangeText()
    }

    private func setIndentLevel(_ level: Int, lineStart: Int, isBullet: Bool) {
        guard let storage = textStorage else { return }
        let indent = CGFloat(level) * ListIndent.width

        // Swap bullet character if needed (• and ◦ are both 1 NSString character)
        if isBullet && lineStart < storage.length {
            let ch = (storage.string as NSString).substring(with: NSRange(location: lineStart, length: 1))
            if level == 0 && ch == "◦" {
                replaceText(in: NSRange(location: lineStart, length: 1), with: "•")
            } else if level > 0 && ch == "•" {
                replaceText(in: NSRange(location: lineStart, length: 1), with: "◦")
            }
        }

        // Apply paragraph indentation
        let paraRange = (storage.string as NSString).paragraphRange(for: NSRange(location: lineStart, length: 0))
        guard shouldChangeText(in: paraRange, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: paraRange) { val, range, _ in
            let style = self.paragraphStyle(basedOn: val as? NSParagraphStyle, isTodoParagraph: !isBullet)
            style.headIndent = indent
            style.firstLineHeadIndent = indent
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        }
        storage.endEditing()
        didChangeText()
        notifyChange()
    }

    private func handleTab(isShift: Bool) -> Bool {
        guard let storage = textStorage else { return false }
        let pos = selectedRange().location
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: pos, length: 0))
        let lineStart = lineRange.location
        guard lineStart < storage.length else { return false }

        let previewLen = min(2, storage.length - lineStart)
        let lineText2 = nsString.substring(with: NSRange(location: lineStart, length: previewLen))
        let isBullet = lineText2.hasPrefix("• ") || lineText2.hasPrefix("◦ ")
        let isTodo = storage.attributes(at: lineStart, effectiveRange: nil)[.attachment] is TodoAttachment

        guard isBullet || isTodo else { return false }

        let currentLevel = indentLevel(at: lineStart)

        if isShift {
            guard currentLevel > 0 else { return false }
            setIndentLevel(currentLevel - 1, lineStart: lineStart, isBullet: isBullet)
        } else {
            guard currentLevel < ListIndent.maxNestingLevel else { return false }
            setIndentLevel(currentLevel + 1, lineStart: lineStart, isBullet: isBullet)
        }
        return true
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
        let sel = clampedSelection(cursorRange, to: storage)

        if let emptyLineRange = emptyCurrentLineContentRange(for: sel) {
            let marker = NSAttributedString(string: "• ", attributes: normalizedTypingAttributes())
            guard replaceText(in: emptyLineRange, with: marker) else { return }
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: emptyLineRange.location + marker.length, length: 0))
            notifyChange()
            return
        }

        let lineRanges = coveredLineRanges(for: sel)

        storage.beginEditing()
        var offset = 0
        for lr in lineRanges {
            let origLineText = (string as NSString).substring(with: lr).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !origLineText.isEmpty else { continue }

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
        let sel = clampedSelection(cursorRange, to: storage)

        if let emptyLineRange = emptyCurrentLineContentRange(for: sel) {
            let todo = todoAttachmentAttributedString()
            guard replaceText(in: emptyLineRange, with: todo) else { return }
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: emptyLineRange.location + todo.length, length: 0))
            notifyChange()
            return
        }

        let lineRanges = coveredLineRanges(for: sel)

        storage.beginEditing()
        var offset = 0
        for lr in lineRanges {
            let origLineText = (string as NSString).substring(with: lr).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !origLineText.isEmpty else { continue }

            let adjStart = lr.location + offset
            guard adjStart <= storage.length else { continue }

            if adjStart < storage.length,
               storage.attributes(at: adjStart, effectiveRange: nil)[.attachment] is TodoAttachment {
                let removeLen = min(2, storage.length - adjStart)
                storage.replaceCharacters(in: NSRange(location: adjStart, length: removeLen), with: "")
                offset -= removeLen
            } else {
                let previewLen = min(2, storage.length - adjStart)
                let lineText = adjStart < storage.length
                    ? (storage.string as NSString).substring(with: NSRange(location: adjStart, length: previewLen))
                    : ""
                let aStr = todoAttachmentAttributedString()
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
        let sel = position ?? (lastKnownSelection.length > 0 ? lastKnownSelection : lastKnownCursorPosition)
        window?.makeFirstResponder(self)
        guard shouldChangeText(in: sel, replacementString: atStr.string) else { return }
        storage.replaceCharacters(in: sel, with: atStr)
        setSelectedRange(NSRange(location: sel.location + atStr.length, length: 0))
        didChangeText()
        typingAttributes = normalizedTypingAttributes()
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

    /// Clamps a raw cursor/selection range to valid storage bounds.
    private func clampedSelection(_ range: NSRange?, to storage: NSTextStorage) -> NSRange {
        let raw = range ?? (lastKnownSelection.length > 0 ? lastKnownSelection : lastKnownCursorPosition)
        let loc = min(raw.location, storage.length)
        return NSRange(location: loc, length: min(raw.length, storage.length - loc))
    }

    /// Returns line ranges for every line covered by the selection (or the line at the cursor).
    private func coveredLineRanges(for sel: NSRange) -> [NSRange] {
        let nsString = string as NSString
        let scanRange = sel.length > 0 ? sel : nsString.lineRange(for: sel)
        var ranges: [NSRange] = []
        var pos = scanRange.location
        while pos <= scanRange.location + scanRange.length {
            let lr = nsString.lineRange(for: NSRange(location: pos, length: 0))
            ranges.append(lr)
            pos = lr.upperBound
            if pos >= scanRange.location + scanRange.length { break }
        }
        return ranges
    }

    /// Returns the editable portion of the current line when the caret is on a blank line.
    /// Trailing line breaks are excluded so list markers are inserted before the newline.
    private func emptyCurrentLineContentRange(for sel: NSRange) -> NSRange? {
        guard sel.length == 0 else { return nil }
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: sel)
        var contentLength = lineRange.length

        while contentLength > 0 {
            let scalar = nsString.character(at: lineRange.location + contentLength - 1)
            guard scalar == 10 || scalar == 13 else { break }
            contentLength -= 1
        }

        let contentRange = NSRange(location: lineRange.location, length: contentLength)
        let lineText = nsString.substring(with: contentRange)
        guard lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return contentRange
    }

    /// Toggles a font trait (bold/italic) on the current selection.
    /// If there is no selection, toggles the trait for future typing via typingAttributes only —
    /// this prevents accidentally bolding text on a different line.
    private func toggleFontTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        let sel = selectedRange()
        guard sel.length > 0, let storage = textStorage else {
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
        buoyDelegate?.textViewDidChange(self)
        let h = measureContentHeight()
        measuredHeight = h
        buoyDelegate?.textViewHeightDidChange(h)
        needsDisplay = true
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting: Bool) {
        lastKnownCursorPosition = charRange
        if charRange.length > 0 {
            lastKnownSelection = charRange
        }
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting {
            buoyDelegate?.textViewSelectionDidChange(self)
        }
    }

    /// NSTextView routes ALL user-driven selection changes (drag, click, shift-click) through
    /// setSelectedRanges (plural), bypassing the singular overrides above.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard let first = ranges.first?.rangeValue else { return }
        lastKnownCursorPosition = first
        if first.length > 0 {
            lastKnownSelection = first
        }
        if !stillSelecting {
            buoyDelegate?.textViewSelectionDidChange(self)
        }
    }

    // MARK: - Plain text export

    func plainTextContent() -> String {
        guard let storage = textStorage else { return string }
        let nsString = storage.string as NSString
        var result = ""
        var location = 0

        while location < storage.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attrs = storage.attributes(at: location, effectiveRange: &effectiveRange)

            if let todo = attrs[.attachment] as? TodoAttachment {
                result += todo.isChecked ? "☑ " : "☐ "
                location = NSMaxRange(effectiveRange)
                if location < storage.length, nsString.character(at: location) == 32 {
                    // Skip the built-in spacer stored after every TodoAttachment so exports stay stable.
                    location += 1
                }
            } else {
                result += nsString.substring(with: effectiveRange)
                location = NSMaxRange(effectiveRange)
            }
        }
        return result
    }

    // MARK: - HTML export (for Apple Notes transfer)

    func htmlContent() -> String {
        guard let storage = textStorage else { return plainTextContent() }
        let mutable = mutableCopyReplacingTodoAttachments(in: storage) { isChecked, _ in
            let symbol = isChecked ? "☑" : "☐"
            return NSAttributedString(string: symbol, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.textColor
            ])
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
        let mutable = mutableCopyReplacingTodoAttachments(in: storage) { isChecked, paraStyle in
            let marker = isChecked ? "\u{2611}" : "\u{2610}"
            return NSAttributedString(string: marker, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle(basedOn: paraStyle, isTodoParagraph: true)
            ])
        }
        return try? mutable.data(
            from: NSRange(location: 0, length: mutable.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// Returns a mutable copy of `storage` with every TodoAttachment replaced using `makeReplacement`.
    /// The attachment's built-in spacer is consumed too so repeated exports don't duplicate it.
    /// Replacements are applied in reverse order to preserve correct indices.
    private func mutableCopyReplacingTodoAttachments(
        in storage: NSTextStorage,
        makeReplacement: (Bool, NSParagraphStyle?) -> NSAttributedString
    ) -> NSMutableAttributedString {
        let mutable = NSMutableAttributedString(attributedString:
            storage.attributedSubstring(from: NSRange(location: 0, length: storage.length)))
        let nsString = storage.string as NSString

        var attachments: [(NSRange, Bool, NSParagraphStyle?)] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { val, range, _ in
            if let todo = val as? TodoAttachment {
                let paraStyle = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
                let replacementRange = rangeByConsumingFollowingTodoSpacer(
                    in: nsString,
                    startingWith: range,
                    consumeAllFollowingSpaces: false
                )
                attachments.append((replacementRange, todo.isChecked, paraStyle))
            }
        }
        for (range, isChecked, paraStyle) in attachments.reversed() {
            mutable.replaceCharacters(in: range, with: makeReplacement(isChecked, paraStyle))
        }
        return mutable
    }

    private func rangeByConsumingFollowingTodoSpacer(
        in string: NSString,
        startingWith baseRange: NSRange,
        consumeAllFollowingSpaces: Bool
    ) -> NSRange {
        var expanded = baseRange
        while NSMaxRange(expanded) < string.length, string.character(at: NSMaxRange(expanded)) == 32 {
            expanded.length += 1
            if !consumeAllFollowingSpaces { break }
        }
        return expanded
    }

    func loadRTF(_ data: Data) {
        guard !data.isEmpty,
              let atStr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              ) else {
            textStorage?.setAttributedString(NSAttributedString(string: ""))
            needsDisplay = true
            return
        }

        let mutable = NSMutableAttributedString(attributedString: atStr)
        let fullRange = NSRange(location: 0, length: mutable.length)

        // Normalize all fonts to system font, preserving bold/italic traits
        mutable.enumerateAttribute(.font, in: fullRange) { val, range, _ in
            guard let font = val as? NSFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            let desc = NSFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(traits)
            let newFont = NSFont(descriptor: desc, size: fontSize)
            mutable.addAttribute(.font, value: newFont ?? NSFont.systemFont(ofSize: fontSize), range: range)
        }

        // Normalize foreground colors to adaptive textColor; re-apply linkColor to link ranges
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
            let style = paragraphStyle(basedOn: val as? NSParagraphStyle)
            styleUpdates.append((range, style))
        }
        for (range, style) in styleUpdates {
            mutable.addAttribute(.paragraphStyle, value: style, range: range)
        }

        // RTF round-trip often loses the font attribute on attachment characters (U+FFFC).
        mutable.enumerateAttribute(.attachment, in: fullRange) { val, range, _ in
            guard val != nil else { return }
            mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize), range: range)
        }

        // Restore TodoAttachments from ☐/☑ markers written by rtfContent().
        // Older builds wrote the marker and left the built-in spacer behind, so consume any
        // following spaces here and canonicalize back to a single attachment + single spacer.
        for (marker, isChecked) in [("\u{2611}", true), ("\u{2610}", false)] as [(String, Bool)] {
            var searchRange = NSRange(location: 0, length: mutable.length)
            while searchRange.location < mutable.length {
                let found = (mutable.string as NSString).range(of: marker, options: [], range: searchRange)
                if found.location == NSNotFound { break }
                let markerParaStyle = mutable.attribute(.paragraphStyle, at: found.location, effectiveRange: nil) as? NSParagraphStyle
                let nestLevel = Int((markerParaStyle?.headIndent ?? 0) / ListIndent.width)
                let atStr = todoAttachmentAttributedString(isChecked: isChecked, indentLevel: nestLevel)
                let replacementRange = rangeByConsumingFollowingTodoSpacer(
                    in: mutable.string as NSString,
                    startingWith: found,
                    consumeAllFollowingSpaces: true
                )
                mutable.replaceCharacters(in: replacementRange, with: atStr)
                let nextLoc = replacementRange.location + atStr.length
                searchRange = NSRange(location: nextLoc, length: mutable.length - nextLoc)
            }
        }

        // Apply todoParagraph spacing to paragraphs that start with a TodoAttachment,
        // preserving headIndent so nested todos survive the RTF round-trip.
        let normalizedString = mutable.string as NSString
        var paragraphStart = 0
        while paragraphStart < mutable.length {
            let paragraphRange = normalizedString.paragraphRange(for: NSRange(location: paragraphStart, length: 0))
            if paragraphRange.location < mutable.length,
               mutable.attribute(.attachment, at: paragraphRange.location, effectiveRange: nil) is TodoAttachment {
                let existingStyle = mutable.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
                mutable.addAttribute(
                    .paragraphStyle,
                    value: paragraphStyle(basedOn: existingStyle, isTodoParagraph: true),
                    range: paragraphRange
                )
            }
            paragraphStart = NSMaxRange(paragraphRange)
        }

        textStorage?.setAttributedString(mutable)
        updateDefaultTypingAttributes()
        needsDisplay = true
    }

    // MARK: - Right-click Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }

        // Remove writing direction / layout orientation items (identified by action selectors,
        // locale-independent — title strings differ across macOS versions and languages).
        for item in menu.items where itemIsWritingDirectionOrLayoutOrientation(item) {
            menu.removeItem(item)
        }

        // Find the existing Transformations submenu by checking for the standard uppercaseWord: action.
        var transformationsItem = menu.items.first { item in
            item.submenu?.items.contains { $0.action == #selector(NSResponder.uppercaseWord(_:)) } == true
        }

        if transformationsItem == nil {
            let sub = NSMenu(title: "Transformations")
            let parent = NSMenuItem(title: "Transformations", action: nil, keyEquivalent: "")
            parent.submenu = sub
            menu.addItem(.separator())
            menu.addItem(parent)
            transformationsItem = parent
        }

        guard let sub = transformationsItem?.submenu else { return menu }

        sub.addItem(.separator())
        let boldItem      = sub.addItem(withTitle: "Bold",      action: #selector(boldAction(_:)),      keyEquivalent: "")
        let italicItem    = sub.addItem(withTitle: "Italic",    action: #selector(italicAction(_:)),    keyEquivalent: "")
        let underlineItem = sub.addItem(withTitle: "Underline", action: #selector(underlineAction(_:)), keyEquivalent: "")
        sub.addItem(.separator())
        let linkItem = sub.addItem(withTitle: "Link…", action: #selector(linkAction(_:)), keyEquivalent: "")

        for item in [boldItem, italicItem, underlineItem, linkItem] {
            item.target = self
        }

        return menu
    }

    private func itemIsWritingDirectionOrLayoutOrientation(_ item: NSMenuItem) -> Bool {
        guard let sub = item.submenu else { return false }
        let writingDirectionActions: [Selector] = [
            #selector(NSResponder.makeBaseWritingDirectionNatural(_:)),
            #selector(NSResponder.makeBaseWritingDirectionLeftToRight(_:)),
            #selector(NSResponder.makeBaseWritingDirectionRightToLeft(_:))
        ]
        return sub.items.contains { $0.action.map { writingDirectionActions.contains($0) } ?? false }
            || sub.items.contains { $0.action == NSSelectorFromString("changeLayoutOrientation:") }
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let formattingActions: Set<Selector> = [
            #selector(boldAction(_:)),
            #selector(italicAction(_:)),
            #selector(underlineAction(_:))
        ]
        if let action = item.action, formattingActions.contains(action) {
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
        buoyDelegate?.textViewRequestShowLinkDialog(selectedText: selected)
    }
}
