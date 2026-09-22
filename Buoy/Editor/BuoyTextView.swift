import AppKit

// MARK: - Link Editing

/// Immutable editor state captured before the floating link panel takes focus.
/// Keeping the range with the text prevents a later responder change from
/// redirecting the insertion to the start of the note.
struct LinkEditingContext {
    /// Range that will receive the link. This may expand to an existing link.
    let range: NSRange
    /// The user's literal highlighted range, kept separate from `range` so a
    /// caret inside an existing link does not masquerade as a selection.
    let highlightedRange: NSRange?
    let text: String
    let url: String

    static let empty = LinkEditingContext(
        range: NSRange(location: 0, length: 0),
        highlightedRange: nil,
        text: "",
        url: ""
    )

    var hasText: Bool { range.length > 0 && !text.isEmpty }
    var isEditingExistingLink: Bool { !url.isEmpty }
}

/// Shared URL normalization for the dialog's validation and the editor write.
enum LinkDestination {
    static func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parsedScheme = URLComponents(string: trimmed)?.scheme
        // URLComponents interprets `localhost:3000` as a custom scheme. Treat
        // that common development-host form as a schemeless web destination.
        let needsWebScheme = parsedScheme?.isEmpty != false
            || parsedScheme?.lowercased() == "localhost"
        let candidate = needsWebScheme ? "https://\(trimmed)" : trimmed
        guard let url = URL(string: candidate), let scheme = url.scheme, !scheme.isEmpty else {
            return nil
        }

        // Web destinations need a host. Other explicit schemes (for example,
        // mailto:) remain available and are handed to NSWorkspace on click.
        if ["http", "https"].contains(scheme.lowercased()), url.host?.isEmpty != false {
            return nil
        }
        return url
    }
}

// MARK: - App-level shortcut notifications

extension Notification.Name {
    static let buoyNewNote         = Notification.Name("BuoyNewNote")
    static let buoyDeleteNote      = Notification.Name("BuoyDeleteNote")
    static let buoyCopyToClipboard = Notification.Name("BuoyCopyToClipboard")
    static let buoyPreviousNote    = Notification.Name("BuoyPreviousNote")
    static let buoyNextNote        = Notification.Name("BuoyNextNote")
    static let buoyPanelBecameKey  = Notification.Name("BuoyPanelBecameKey")
}

// MARK: - Delegate Protocol

protocol BuoyTextViewDelegate: AnyObject {
    func textViewDidChange(_ textView: BuoyTextView)
    func textViewSelectionDidChange(_ textView: BuoyTextView)
    func textViewRequestShowLinkDialog(context: LinkEditingContext)
}

// MARK: - BuoyTextView

final class BuoyTextView: NSTextView {
    private enum EditorSpacing {
        static let line: CGFloat = 4
        static let paragraph: CGFloat = 0
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

    var usesDarkAppearance = false {
        didSet {
            guard usesDarkAppearance != oldValue else { return }
            refreshResolvedEditorColors()
        }
    }

    var placeholderString = "Let your words flow..."

    /// When true, forces the arrow cursor instead of the I-beam — set while an
    /// overlay panel (Settings, Shortcuts, All Notes) is presented so its own
    /// hover states aren't fought by this view's tracking area underneath.
    var suppressesIBeamCursor = false {
        didSet {
            guard suppressesIBeamCursor != oldValue else { return }
            if suppressesIBeamCursor {
                NSCursor.arrow.set()
            } else {
                window?.invalidateCursorRects(for: self)
            }
        }
    }

    private var themeObserver: NSObjectProtocol?
    private lazy var listReorder = ListReorderController(textView: self)

    deinit {
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
    }
    var currentEditorTextColor: NSColor { editorTextColor }

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
        isEditable = true
        isSelectable = true
        allowsUndo = true
        applyTextCheckingPreferences()

        // No `usesFindBar`. AppKit's find bar has a hard intrinsic minimum width
        // (search field + prev/next + Done) that is wider than Buoy's 292pt
        // minimum panel, so it cannot compress: it overflows the scroll view and,
        // because the editor is not clipped to the glass shape, paints outside
        // the window entirely while the panel is resized. A find UI here has to
        // be built to Buoy's own chrome rather than inherited.
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
            .backgroundColor: BuoyTheme.current.accentNSColor.withAlphaComponent(0.35)
        ]
        linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        insertionPointColor = editorTextColor
        setAccessibilityLabel("Note")
        updateDefaultTypingAttributes()
        themeObserver = NotificationCenter.default.addObserver(
            forName: .buoyThemeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyThemeColors()
        }
    }

    /// Re-applies everything the accent colour reaches inside the editor.
    ///
    /// None of this comes from the SwiftUI environment, so a colour change has
    /// to be pushed in. The to-do checkboxes are the awkward part: each one
    /// bakes its colours into an `NSImage` when it is built, so every
    /// attachment in the storage has to be asked to redraw itself.
    private func applyThemeColors() {
        selectedTextAttributes = [
            .backgroundColor: BuoyTheme.current.accentNSColor.withAlphaComponent(0.35)
        ]
        guard let storage = textStorage else { return }
        storage.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: storage.length)
        ) { value, _, _ in
            (value as? TodoAttachment)?.refreshForThemeChange()
        }
        needsDisplay = true
    }

    // MARK: - Text Checking Preferences
    //
    // NSTextView's spelling and substitution flags live on the instance, and
    // Buoy remounts the editor whenever the note changes, so anything the user
    // switched on from Edit ▸ Spelling and Grammar would silently revert on the
    // next note. These persist the flags and replay them onto each new instance.

    enum TextCheckingOption: String, CaseIterable {
        case continuousSpellChecking
        case grammarChecking
        case automaticSpellingCorrection
        case smartInsertDelete
        case automaticQuoteSubstitution
        case automaticDashSubstitution
        case automaticLinkDetection
        case automaticTextReplacement

        /// Buoy's shipped defaults. Spell checking matches every other macOS
        /// text editor; the substitution options stay off because reformatting
        /// what someone typed into a scratch note is rarely wanted. All of them
        /// are now reachable from the Edit menu either way.
        var defaultValue: Bool {
            switch self {
            case .continuousSpellChecking, .automaticLinkDetection: return true
            default: return false
            }
        }

        fileprivate var defaultsKey: String { "buoy.textChecking.\(rawValue)" }

        fileprivate var current: Bool {
            UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? defaultValue
        }

        fileprivate func store(_ value: Bool) {
            UserDefaults.standard.set(value, forKey: defaultsKey)
        }
    }

    private func applyTextCheckingPreferences() {
        isContinuousSpellCheckingEnabled = TextCheckingOption.continuousSpellChecking.current
        isGrammarCheckingEnabled = TextCheckingOption.grammarChecking.current
        isAutomaticSpellingCorrectionEnabled = TextCheckingOption.automaticSpellingCorrection.current
        smartInsertDeleteEnabled = TextCheckingOption.smartInsertDelete.current
        isAutomaticQuoteSubstitutionEnabled = TextCheckingOption.automaticQuoteSubstitution.current
        isAutomaticDashSubstitutionEnabled = TextCheckingOption.automaticDashSubstitution.current
        isAutomaticLinkDetectionEnabled = TextCheckingOption.automaticLinkDetection.current
        isAutomaticTextReplacementEnabled = TextCheckingOption.automaticTextReplacement.current
    }

    override func toggleContinuousSpellChecking(_ sender: Any?) {
        super.toggleContinuousSpellChecking(sender)
        TextCheckingOption.continuousSpellChecking.store(isContinuousSpellCheckingEnabled)
    }

    override func toggleGrammarChecking(_ sender: Any?) {
        super.toggleGrammarChecking(sender)
        TextCheckingOption.grammarChecking.store(isGrammarCheckingEnabled)
    }

    override func toggleAutomaticSpellingCorrection(_ sender: Any?) {
        super.toggleAutomaticSpellingCorrection(sender)
        TextCheckingOption.automaticSpellingCorrection.store(isAutomaticSpellingCorrectionEnabled)
    }

    override func toggleSmartInsertDelete(_ sender: Any?) {
        super.toggleSmartInsertDelete(sender)
        TextCheckingOption.smartInsertDelete.store(smartInsertDeleteEnabled)
    }

    override func toggleAutomaticQuoteSubstitution(_ sender: Any?) {
        super.toggleAutomaticQuoteSubstitution(sender)
        TextCheckingOption.automaticQuoteSubstitution.store(isAutomaticQuoteSubstitutionEnabled)
    }

    override func toggleAutomaticDashSubstitution(_ sender: Any?) {
        super.toggleAutomaticDashSubstitution(sender)
        TextCheckingOption.automaticDashSubstitution.store(isAutomaticDashSubstitutionEnabled)
    }

    override func toggleAutomaticLinkDetection(_ sender: Any?) {
        super.toggleAutomaticLinkDetection(sender)
        TextCheckingOption.automaticLinkDetection.store(isAutomaticLinkDetectionEnabled)
    }

    override func toggleAutomaticTextReplacement(_ sender: Any?) {
        super.toggleAutomaticTextReplacement(sender)
        TextCheckingOption.automaticTextReplacement.store(isAutomaticTextReplacementEnabled)
    }

    private var editorTextColor: NSColor {
        if #available(macOS 26, *) {
            return NSColor.textColor
        } else {
            return usesDarkAppearance ? .white : .black
        }
    }

    /// Placeholder colour: muted, but fully opaque.
    ///
    /// Translucency is what fails here. Buoy's editor sits on glass, so below
    /// 100% alpha the desktop shows *through the letterforms* and the text takes
    /// on whatever is behind the window — which is why `placeholderTextColor`
    /// (~25%) and `secondaryLabelColor` (~55%) both disappeared over a bright
    /// backdrop. The "faded" reading comes from the colour being grey, never
    /// from alpha, so every glyph stays solid regardless of the backdrop.
    private var editorPlaceholderColor: NSColor {
        let level: CGFloat = usesDarkAppearance
            ? (BuoyContrast.isIncreased ? 0.82 : 0.64)
            : (BuoyContrast.isIncreased ? 0.20 : 0.38)
        return NSColor(white: level, alpha: 1)
    }

    private func refreshResolvedEditorColors() {
        guard let storage = textStorage else {
            insertionPointColor = editorTextColor
            typingAttributes = normalizedTypingAttributes(basedOn: typingAttributes)
            needsDisplay = true
            return
        }

        if storage.length > 0 {
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.foregroundColor, range: fullRange)
            storage.addAttribute(.foregroundColor, value: editorTextColor, range: fullRange)
            storage.enumerateAttribute(.link, in: fullRange) { val, range, _ in
                if val != nil {
                    storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
                }
            }
            storage.endEditing()
        }

        insertionPointColor = editorTextColor
        typingAttributes = normalizedTypingAttributes(basedOn: typingAttributes)
        needsDisplay = true
    }

    override var needsPanelToBecomeKey: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // MARK: - Cursor

    override func cursorUpdate(with event: NSEvent) {
        guard !suppressesIBeamCursor else { return }
        super.cursorUpdate(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard !suppressesIBeamCursor else { return }
        super.mouseMoved(with: event)
    }

    private func updateDefaultTypingAttributes() {
        typingAttributes = normalizedTypingAttributes()
    }

    private func systemFont(
        ofSize size: CGFloat? = nil,
        preserving traits: NSFontDescriptor.SymbolicTraits = []
    ) -> NSFont {
        let resolvedSize = size ?? fontSize
        let base = NSFont.systemFont(ofSize: resolvedSize)
        let supportedTraits: NSFontDescriptor.SymbolicTraits = [.bold, .italic]
        let preservedTraits = traits.intersection(supportedTraits)
        guard !preservedTraits.isEmpty else { return base }

        let descriptor = base.fontDescriptor.withSymbolicTraits(preservedTraits)
        return NSFont(descriptor: descriptor, size: resolvedSize) ?? base
    }

    private func systemFont(
        ofSize size: CGFloat? = nil,
        preservingTraitsFrom source: NSFont?
    ) -> NSFont {
        systemFont(
            ofSize: size,
            preserving: source?.fontDescriptor.symbolicTraits ?? []
        )
    }

    private func paragraphStyle(
        basedOn source: NSParagraphStyle? = nil,
        isTodoParagraph _: Bool = false
    ) -> NSMutableParagraphStyle {
        let style = (source?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        // Rich text copied from browsers and document editors can carry several
        // independent vertical-spacing values. Reset all of them so imported text
        // lays out exactly like text typed in Buoy, while preserving non-vertical
        // paragraph attributes such as list indentation and writing direction.
        style.lineSpacing = EditorSpacing.line
        // Todo attachments already fit inside the normal line fragment. Giving
        // them paragraph spacing here makes checklist rows visibly farther apart.
        style.paragraphSpacing = EditorSpacing.paragraph
        style.paragraphSpacingBefore = 0
        style.minimumLineHeight = 0
        style.maximumLineHeight = 0
        style.lineHeightMultiple = 0
        style.textBlocks = []
        return style
    }

    /// Applies Buoy's vertical-spacing contract to every paragraph touched by `range`.
    /// Paragraph ranges are expanded to their boundaries because AppKit resolves these
    /// attributes per paragraph, even when pasted rich text splits one into several runs.
    private func normalizeParagraphSpacing(
        in attributedString: NSMutableAttributedString,
        range: NSRange
    ) {
        guard attributedString.length > 0, range.length > 0 else { return }

        let clampedStart = min(max(range.location, 0), attributedString.length - 1)
        let clampedEnd = min(max(NSMaxRange(range), clampedStart + 1), attributedString.length)
        let nsString = attributedString.string as NSString
        let firstParagraph = nsString.paragraphRange(for: NSRange(location: clampedStart, length: 0))
        let lastParagraph = nsString.paragraphRange(
            for: NSRange(location: max(clampedStart, clampedEnd - 1), length: 0)
        )
        let affectedEnd = NSMaxRange(lastParagraph)

        var updates: [(NSRange, NSMutableParagraphStyle)] = []
        var paragraphStart = firstParagraph.location
        while paragraphStart < affectedEnd, paragraphStart < attributedString.length {
            let paragraphRange = nsString.paragraphRange(
                for: NSRange(location: paragraphStart, length: 0)
            )
            let isTodoParagraph = attributedString.attribute(
                .attachment,
                at: paragraphRange.location,
                effectiveRange: nil
            ) is TodoAttachment

            attributedString.enumerateAttribute(.paragraphStyle, in: paragraphRange) { value, attributeRange, _ in
                updates.append((
                    attributeRange,
                    paragraphStyle(
                        basedOn: value as? NSParagraphStyle,
                        isTodoParagraph: isTodoParagraph
                    )
                ))
            }

            let next = NSMaxRange(paragraphRange)
            guard next > paragraphStart else { break }
            paragraphStart = next
        }

        for (attributeRange, style) in updates {
            attributedString.addAttribute(.paragraphStyle, value: style, range: attributeRange)
        }
    }

    private func todoAttachmentAttributedString(isChecked: Bool = false, indentLevel: Int = 0) -> NSMutableAttributedString {
        let indent = CGFloat(indentLevel) * ListIndent.width
        let para = paragraphStyle(isTodoParagraph: true)
        para.headIndent = indent
        para.firstLineHeadIndent = indent

        let attachment = TodoAttachment(isChecked: isChecked, fontSize: fontSize)
        let atStr = NSMutableAttributedString(attachment: attachment)
        atStr.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize),
                           range: NSRange(location: 0, length: atStr.length))
        atStr.addAttribute(.paragraphStyle, value: para,
                           range: NSRange(location: 0, length: atStr.length))
        let spacer = NSAttributedString(string: " ", attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: editorTextColor,
            .paragraphStyle: para
        ])
        atStr.append(spacer)
        return atStr
    }

    private func normalizedTypingAttributes(
        basedOn source: [NSAttributedString.Key: Any]? = nil
    ) -> [NSAttributedString.Key: Any] {
        let style = paragraphStyle(basedOn: source?[.paragraphStyle] as? NSParagraphStyle)
        let font = systemFont(
            preservingTraitsFrom: source?[.font] as? NSFont
        )

        var attrs = source ?? [:]
        attrs[.font] = font
        attrs[.foregroundColor] = editorTextColor
        attrs[.paragraphStyle] = style
        attrs.removeValue(forKey: .attachment)
        attrs.removeValue(forKey: .backgroundColor)
        attrs.removeValue(forKey: .link)
        attrs.removeValue(forKey: .baselineOffset)
        attrs.removeValue(forKey: NSAttributedString.Key("NSSuperscript"))
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
            storage.addAttribute(
                .font,
                value: systemFont(preservingTraitsFrom: font),
                range: range
            )
        }
        storage.enumerateAttribute(.attachment, in: fullRange) { val, _, _ in
            (val as? TodoAttachment)?.apply(fontSize: fontSize)
        }
        storage.endEditing()
        // Attachment bounds changed; force a relayout so the new checkbox size takes effect.
        layoutManager?.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        layoutManager?.invalidateDisplay(forCharacterRange: fullRange)
        // Defer content change to avoid modifying @Observable state during SwiftUI render.
        // Reports content only — font size is attribute-only, so it must not auto-grow
        // the window (same rule as formatting toggles).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.buoyDelegate?.textViewDidChange(self)
            self.needsDisplay = true
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
            .foregroundColor: editorPlaceholderColor
        ])
    }

    // MARK: - Key Equivalents (command keys — intercepted before NSTextView default handling)

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only handle key equivalents when this text view is the first responder.
        // Otherwise, events meant for other focused views (e.g. the search field in
        // AllNotesPanel) get swallowed by the editor behind the overlay.
        guard window?.firstResponder == self else {
            return false
        }

        // Strip noise flags — numericPad/function/help on arrow keys, capsLock always
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .help, .capsLock])

        // ⌘⇧Z — redo (must check before the .command-only guard below)
        if mods == [.command, .shift] && event.keyCode == 6 {
            undoManager?.redo()
            return true
        }

        // ⌘⇧X — strikethrough (must check before the .command-only guard below)
        if mods == [.command, .shift] && event.keyCode == 7 {
            applyStrikethrough()
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

        // Previous/next note used to be matched here too. The panel claims
        // every rebindable command before the responder chain sees the event,
        // so there is nothing left for this view to intercept.
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Key Down Handling

    override func keyDown(with event: NSEvent) {
        let chars = event.characters ?? ""
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // New note, delete, copy and Insert Link used to be matched here as
        // well as in `BuoyPanel.performKeyEquivalent`. They are the user's to
        // rebind now, so the panel's registry lookup owns them outright — a
        // second copy here would keep firing on the old keys.

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

    // MARK: - List drag-to-reorder

    /// Whether the paragraph starting at `paragraphStart` is a todo or bullet line.
    func isListParagraph(at paragraphStart: Int) -> Bool {
        guard let storage = textStorage, paragraphStart < storage.length else { return false }
        if storage.attributes(at: paragraphStart, effectiveRange: nil)[.attachment] is TodoAttachment {
            return true
        }
        let nsString = storage.string as NSString
        let previewLen = min(2, storage.length - paragraphStart)
        let prefix = nsString.substring(with: NSRange(location: paragraphStart, length: previewLen))
        return prefix.hasPrefix("• ") || prefix.hasPrefix("◦ ")
    }

    /// The maximal run of consecutive list paragraphs (todo or bullet) containing `charIndex`.
    func listBlock(containing charIndex: Int) -> ListBlock? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let nsString = storage.string as NSString
        let clamped = min(max(charIndex, 0), storage.length - 1)
        var current = nsString.paragraphRange(for: NSRange(location: clamped, length: 0))
        guard isListParagraph(at: current.location) else { return nil }

        var paragraphs = [current]

        while current.location > 0 {
            let prev = nsString.paragraphRange(for: NSRange(location: current.location - 1, length: 0))
            guard isListParagraph(at: prev.location) else { break }
            paragraphs.insert(prev, at: 0)
            current = prev
        }

        current = paragraphs[paragraphs.count - 1]
        while NSMaxRange(current) < storage.length {
            let next = nsString.paragraphRange(for: NSRange(location: NSMaxRange(current), length: 0))
            guard next.length > 0, isListParagraph(at: next.location) else { break }
            paragraphs.append(next)
            current = next
        }

        let range = NSRange(location: paragraphs[0].location, length: NSMaxRange(paragraphs[paragraphs.count - 1]) - paragraphs[0].location)
        return ListBlock(paragraphs: paragraphs, range: range)
    }

    /// Moves the paragraph at `sourceIndex` within `block` to `targetBoundary` (0...paragraphs.count),
    /// rebuilding the whole block as a single undoable edit.
    func commitListReorder(block: ListBlock, sourceIndex: Int, targetBoundary: Int) {
        guard let storage = textStorage,
              sourceIndex >= 0, sourceIndex < block.paragraphs.count,
              targetBoundary >= 0, targetBoundary <= block.paragraphs.count,
              targetBoundary != sourceIndex, targetBoundary != sourceIndex + 1,
              NSMaxRange(block.range) <= storage.length else { return }

        var lines: [(line: NSAttributedString, newline: NSAttributedString?)] = []
        for para in block.paragraphs {
            let full = storage.attributedSubstring(from: para)
            if full.length > 0, (full.string as NSString).character(at: full.length - 1) == 10 {
                let lineRange = NSRange(location: 0, length: full.length - 1)
                let newlineRange = NSRange(location: full.length - 1, length: 1)
                lines.append((full.attributedSubstring(from: lineRange), full.attributedSubstring(from: newlineRange)))
            } else {
                lines.append((full, nil))
            }
        }
        let blockHadTrailingNewline = lines.last?.newline != nil

        let insertIndex = targetBoundary > sourceIndex ? targetBoundary - 1 : targetBoundary
        let moved = lines.remove(at: sourceIndex)
        lines.insert(moved, at: insertIndex)

        let rebuilt = NSMutableAttributedString()
        var caretOffsetForInsertIndex: Int?
        for (i, entry) in lines.enumerated() {
            if i == insertIndex {
                caretOffsetForInsertIndex = rebuilt.length + entry.line.length
            }
            rebuilt.append(entry.line)
            let isLast = (i == lines.count - 1)
            if !isLast || blockHadTrailingNewline {
                if let newline = entry.newline {
                    rebuilt.append(newline)
                } else {
                    var attrs = entry.line.length > 0
                        ? entry.line.attributes(at: entry.line.length - 1, effectiveRange: nil)
                        : typingAttributes
                    attrs.removeValue(forKey: .attachment)
                    attrs.removeValue(forKey: .link)
                    attrs.removeValue(forKey: .backgroundColor)
                    rebuilt.append(NSAttributedString(string: "\n", attributes: attrs))
                }
            }
        }

        guard shouldChangeText(in: block.range, replacementString: rebuilt.string) else { return }
        storage.replaceCharacters(in: block.range, with: rebuilt)
        didChangeText()

        if let offset = caretOffsetForInsertIndex {
            setSelectedRange(NSRange(location: block.range.location + offset, length: 0))
        }
        notifyChange()
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

    // MARK: - Mouse Down (toggle checkboxes / drag-to-reorder list markers)

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let layout = layoutManager, let container = textContainer, let storage = textStorage {
            let glyphIndex = layout.glyphIndex(for: point, in: container,
                                               fractionOfDistanceThroughGlyph: nil)
            if glyphIndex < layout.numberOfGlyphs {
                let charIndex = layout.characterIndexForGlyph(at: glyphIndex)
                if charIndex < storage.length {
                    let isTodo = storage.attributes(at: charIndex, effectiveRange: nil)[.attachment] is TodoAttachment
                    let isBullet = isBulletMarkerCharacter(at: charIndex)
                    if isTodo || isBullet {
                        if handleMarkerPress(event: event, charIndex: charIndex, isTodo: isTodo) {
                            return
                        }
                    }
                }
            }
        }
        super.mouseDown(with: event)
    }

    /// Whether `charIndex` is the bullet glyph ("•"/"◦") at the start of its paragraph.
    private func isBulletMarkerCharacter(at charIndex: Int) -> Bool {
        guard let storage = textStorage, charIndex < storage.length else { return false }
        let nsString = storage.string as NSString
        let ch = nsString.substring(with: NSRange(location: charIndex, length: 1))
        guard ch == "•" || ch == "◦" else { return false }
        let paraRange = nsString.paragraphRange(for: NSRange(location: charIndex, length: 0))
        return paraRange.location == charIndex
    }

    /// Handles a mouse-down on a todo checkbox or bullet marker glyph. A plain click (released
    /// before crossing a small movement threshold) toggles the checkbox / places the caret;
    /// dragging past the threshold reorders the line within its contiguous list block.
    /// Returns true if the event was fully handled (caller should not fall through to super).
    private func handleMarkerPress(event: NSEvent, charIndex: Int, isTodo: Bool) -> Bool {
        guard let window = window else { return false }
        let paraRange = (string as NSString).paragraphRange(for: NSRange(location: charIndex, length: 0))
        guard isListParagraph(at: paraRange.location) else { return false }

        let pressLocation = event.locationInWindow
        let dragThreshold: CGFloat = 4

        while true {
            guard let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { return true }

            switch next.type {
            case .leftMouseUp:
                if isTodo, let storage = textStorage,
                   let todo = storage.attributes(at: charIndex, effectiveRange: nil)[.attachment] as? TodoAttachment {
                    todo.isChecked.toggle()
                    storage.edited(.editedAttributes, range: NSRange(location: charIndex, length: 1), changeInLength: 0)
                    notifyChange()
                } else {
                    window.makeFirstResponder(self)
                    setSelectedRange(NSRange(location: charIndex, length: 0))
                }
                return true
            case .leftMouseDragged:
                let dx = next.locationInWindow.x - pressLocation.x
                let dy = next.locationInWindow.y - pressLocation.y
                if (dx * dx + dy * dy) >= dragThreshold * dragThreshold {
                    guard let block = listBlock(containing: paraRange.location),
                          let sourceIndex = block.paragraphs.firstIndex(where: { $0 == paraRange }) else {
                        return true
                    }
                    if let targetBoundary = listReorder.runReorderDragLoop(
                        block: block, sourceIndex: sourceIndex, firstDragEvent: next
                    ) {
                        commitListReorder(block: block, sourceIndex: sourceIndex, targetBoundary: targetBoundary)
                    }
                    return true
                }
            default:
                break
            }
        }
    }

    // MARK: - Paste

    override func paste(_ sender: Any?) {
        guard let storage = textStorage else { super.paste(sender); return }
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

        if (isBulletLine || isTodoLine),
           let pasted = NSPasteboard.general.string(forType: .string) {
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
            super.paste(sender)
        }
    }

    /// Handles every AppKit pasteboard import path, including regular paste, Paste and
    /// Match Style, rich-text paste, Services, and text dropped into the editor.
    override func readSelection(
        from pasteboard: NSPasteboard,
        type: NSPasteboard.PasteboardType
    ) -> Bool {
        guard let storage = textStorage else {
            return super.readSelection(from: pasteboard, type: type)
        }

        let replacementRange = rangeForUserTextChange
        let previousLength = storage.length
        let didRead = super.readSelection(from: pasteboard, type: type)
        guard didRead,
              replacementRange.location != NSNotFound,
              replacementRange.location <= previousLength,
              replacementRange.length <= previousLength - replacementRange.location else {
            return didRead
        }

        let insertedLength = storage.length - (previousLength - replacementRange.length)
        guard insertedLength > 0,
              replacementRange.location + insertedLength <= storage.length else {
            return didRead
        }

        normalizeImportedContent(
            in: NSRange(location: replacementRange.location, length: insertedLength)
        )
        return didRead
    }

    /// Normalizes imported rich text while retaining supported inline formatting and
    /// non-vertical paragraph details such as list indentation.
    private func normalizeImportedContent(in range: NSRange) {
        guard let storage = textStorage, range.length > 0,
              NSMaxRange(range) <= storage.length else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { val, attrRange, _ in
            storage.addAttribute(
                .font,
                value: systemFont(preservingTraitsFrom: val as? NSFont),
                range: attrRange
            )
        }
        storage.addAttribute(.foregroundColor, value: editorTextColor, range: range)
        storage.removeAttribute(.backgroundColor, range: range)
        storage.removeAttribute(.baselineOffset, range: range)
        storage.removeAttribute(NSAttributedString.Key("NSSuperscript"), range: range)
        normalizeParagraphSpacing(in: storage, range: range)
        canonicalizeExternalBulletLists(in: storage, range: range)
        storage.endEditing()
        notifyChange()
    }

    /// Converts native AppKit text lists from pasted rich text into Buoy's literal bullet markers
    /// so they survive editor teardown/rebuild cycles like Harbor Mode.
    private func canonicalizeExternalBulletLists(
        in attributedString: NSMutableAttributedString,
        range: NSRange
    ) {
        guard attributedString.length > 0, range.length > 0 else { return }

        let clampedStart = min(max(range.location, 0), max(attributedString.length - 1, 0))
        let clampedEnd = min(NSMaxRange(range), attributedString.length)
        guard clampedStart < clampedEnd else { return }

        let nsString = attributedString.string as NSString
        var paragraphStarts: [Int] = []
        var position = clampedStart

        while position < clampedEnd {
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: position, length: 0))
            paragraphStarts.append(paragraphRange.location)
            let next = NSMaxRange(paragraphRange)
            guard next > position else { break }
            position = next
        }

        for paragraphStart in paragraphStarts.reversed() {
            guard paragraphStart < attributedString.length else { continue }

            let currentNSString = attributedString.string as NSString
            let paragraphRange = currentNSString.paragraphRange(for: NSRange(location: paragraphStart, length: 0))
            let existingStyle = attributedString.attribute(.paragraphStyle, at: paragraphStart, effectiveRange: nil) as? NSParagraphStyle
            guard let existingStyle, !existingStyle.textLists.isEmpty else { continue }

            let lineText = currentNSString.substring(with: paragraphRange).trimmingCharacters(in: .newlines)
            guard !lineText.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            if attributedString.attribute(.attachment, at: paragraphStart, effectiveRange: nil) is TodoAttachment {
                continue
            }

            let indentLevel = min(
                max(existingStyle.textLists.count - 1, 0),
                ListIndent.maxNestingLevel
            )
            let marker = indentLevel == 0 ? "• " : "◦ "

            let normalizedStyle = paragraphStyle(basedOn: existingStyle)
            normalizedStyle.textLists = []
            normalizedStyle.headIndent = CGFloat(indentLevel) * ListIndent.width
            normalizedStyle.firstLineHeadIndent = CGFloat(indentLevel) * ListIndent.width

            var markerAttributes = normalizedTypingAttributes(
                basedOn: attributedString.attributes(at: paragraphStart, effectiveRange: nil)
            )
            markerAttributes[.paragraphStyle] = normalizedStyle

            let lineWithoutNewlines = currentNSString.substring(with: paragraphRange).trimmingCharacters(in: .newlines)
            let fullLineRange = NSRange(location: paragraphStart, length: lineWithoutNewlines.utf16.count)

            if let regex = try? NSRegularExpression(pattern: #"^[\t ]*[•◦]\h+"#) {
                let existingMarkerRange = regex.firstMatch(in: attributedString.string, options: [], range: fullLineRange)?.range
                if let existingMarkerRange {
                    attributedString.replaceCharacters(
                        in: existingMarkerRange,
                        with: NSAttributedString(string: marker, attributes: markerAttributes)
                    )
                } else {
                    attributedString.insert(NSAttributedString(string: marker, attributes: markerAttributes), at: paragraphStart)
                }
            } else {
                attributedString.insert(NSAttributedString(string: marker, attributes: markerAttributes), at: paragraphStart)
            }

            let updatedParagraphRange = (attributedString.string as NSString).paragraphRange(
                for: NSRange(location: paragraphStart, length: 0)
            )
            attributedString.addAttribute(.paragraphStyle, value: normalizedStyle, range: updatedParagraphRange)
        }
    }

    // MARK: - Formatting Actions

    func applyBold()   { toggleFontTrait(.bold) }
    func applyItalic() { toggleFontTrait(.italic) }

    func applyUnderline() {
        let sel = selectedRange()
        guard sel.length > 0, let storage = textStorage else {
            // No selection — toggle underline in typingAttributes for future typing
            var attrs = typingAttributes
            if let existing = attrs[.underlineStyle] as? Int,
               existing == NSUnderlineStyle.single.rawValue {
                attrs.removeValue(forKey: .underlineStyle)
            } else {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            typingAttributes = attrs
            return
        }
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

    /// Toggles strikethrough on the current selection. Checklist circles (TodoAttachment)
    /// are exempt — the line is never drawn through the checkbox glyph. Strikethrough is a
    /// standalone attribute, so it composes freely with bold/italic/underline.
    func applyStrikethrough() {
        let sel = selectedRange()
        guard sel.length > 0, let storage = textStorage else {
            // No selection — toggle strikethrough in typingAttributes for future typing
            var attrs = typingAttributes
            if let existing = attrs[.strikethroughStyle] as? Int,
               existing == NSUnderlineStyle.single.rawValue {
                attrs.removeValue(forKey: .strikethroughStyle)
            } else {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            typingAttributes = attrs
            return
        }

        // Collect eligible sub-ranges, skipping any checklist-circle attachment characters.
        var textRanges: [NSRange] = []
        storage.enumerateAttribute(.attachment, in: sel) { val, range, _ in
            if val is TodoAttachment { return }
            textRanges.append(range)
        }
        guard !textRanges.isEmpty else { return }

        var allStruck = true
        for range in textRanges {
            storage.enumerateAttribute(.strikethroughStyle, in: range) { val, _, _ in
                if val == nil { allStruck = false }
            }
        }

        guard shouldChangeText(in: sel, replacementString: nil) else { return }
        storage.beginEditing()
        for range in textRanges {
            if allStruck {
                storage.removeAttribute(.strikethroughStyle, range: range)
            } else {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
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

    /// Captures the current cursor/selection and, when it sits on one link,
    /// expands to that link's full range so invoking Add Link edits it in place.
    func linkEditingContext() -> LinkEditingContext {
        guard let storage = textStorage else { return .empty }
        let capturedRange = clampedSelection(lastKnownCursorPosition, to: storage)
        let highlightedRange = capturedRange.length > 0 ? capturedRange : nil
        var range = capturedRange
        var existingLink: Any?

        if storage.length > 0 {
            if range.length > 0 {
                var effectiveRange = NSRange(location: 0, length: 0)
                let candidate = storage.attribute(
                    .link,
                    at: range.location,
                    longestEffectiveRange: &effectiveRange,
                    in: NSRange(location: 0, length: storage.length)
                )
                if candidate != nil,
                   effectiveRange.location <= range.location,
                   NSMaxRange(effectiveRange) >= NSMaxRange(range) {
                    range = effectiveRange
                    existingLink = candidate
                }
            } else {
                // A caret inside a link, at its leading edge, or immediately
                // after its final character edits the whole link.
                let locations = [
                    range.location < storage.length ? range.location : nil,
                    range.location > 0 ? range.location - 1 : nil
                ].compactMap { $0 }
                for attributeLocation in locations {
                    var effectiveRange = NSRange(location: 0, length: 0)
                    let candidate = storage.attribute(
                        .link,
                        at: attributeLocation,
                        longestEffectiveRange: &effectiveRange,
                        in: NSRange(location: 0, length: storage.length)
                    )
                    if candidate != nil,
                       range.location >= effectiveRange.location,
                       range.location <= NSMaxRange(effectiveRange) {
                        range = effectiveRange
                        existingLink = candidate
                        break
                    }
                }
            }
        }

        let selectedText = range.length > 0
            ? (storage.string as NSString).substring(with: range)
            : ""
        let existingURL: String
        if let url = existingLink as? URL {
            existingURL = url.absoluteString
        } else if let url = existingLink as? String {
            existingURL = url
        } else {
            existingURL = ""
        }
        return LinkEditingContext(
            range: range,
            highlightedRange: highlightedRange,
            text: selectedText,
            url: existingURL
        )
    }

    /// Returns a tiny anchor at the visual center of the selected glyphs that
    /// are currently visible. Weighting each line fragment by its highlighted
    /// area keeps multi-line selections centered on the selection itself rather
    /// than on the empty space inside its overall bounding box.
    func linkPopoverAnchorRect(for range: NSRange) -> NSRect? {
        guard range.length > 0,
              let storage = textStorage,
              let layoutManager,
              let textContainer else { return nil }

        let selection = clampedSelection(range, to: storage)
        guard selection.length > 0 else { return nil }

        layoutManager.ensureLayout(forCharacterRange: selection)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: selection,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return nil }

        let containerOrigin = textContainerOrigin
        let viewport = visibleRect
        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0
        var totalArea: CGFloat = 0

        func include(_ containerRect: NSRect) {
            let viewRect = containerRect.offsetBy(
                dx: containerOrigin.x,
                dy: containerOrigin.y
            )
            let visibleSelection = viewRect.intersection(viewport)
            guard !visibleSelection.isNull, !visibleSelection.isEmpty else { return }
            let area = max(visibleSelection.width, 2) * max(visibleSelection.height, 2)
            weightedX += visibleSelection.midX * area
            weightedY += visibleSelection.midY * area
            totalArea += area
        }

        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: glyphRange,
            in: textContainer
        ) { rect, _ in
            include(rect)
        }

        if totalArea == 0 {
            include(layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer))
        }
        guard totalArea > 0 else { return nil }

        let center = NSPoint(x: weightedX / totalArea, y: weightedY / totalArea)
        return NSRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2)
    }

    func insertLink(text: String, url: String, at position: NSRange? = nil) {
        guard let storage = textStorage else { return }
        guard let finalURL = LinkDestination.normalizedURL(from: url) else { return }
        let display = text.isEmpty ? finalURL.absoluteString : text
        let sel = clampedSelection(position, to: storage)
        var attrs = normalizedPlainTextAttributes(at: min(sel.location, storage.length))
        attrs[.foregroundColor] = NSColor.linkColor
        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        attrs[.link] = finalURL
        window?.makeFirstResponder(self)

        let selectedText = sel.length > 0
            ? (storage.string as NSString).substring(with: sel)
            : ""
        if sel.length > 0 && selectedText == display {
            // Adding or editing a destination doesn't need to rebuild the text.
            // Attribute the existing characters so mixed bold/italic styling is
            // preserved across the operation.
            guard shouldChangeText(in: sel, replacementString: nil) else { return }
            storage.beginEditing()
            storage.addAttributes([
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: finalURL
            ], range: sel)
            storage.endEditing()
        } else {
            let attributedLink = NSAttributedString(string: display, attributes: attrs)
            guard shouldChangeText(in: sel, replacementString: attributedLink.string) else { return }
            storage.replaceCharacters(in: sel, with: attributedLink)
        }
        setSelectedRange(NSRange(location: sel.location + (display as NSString).length, length: 0))
        didChangeText()
        typingAttributes = normalizedTypingAttributes()
    }

    // MARK: - Height Measurement

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
                let normalizedFont = systemFont(preservingTraitsFrom: font)
                let traits = normalizedFont.fontDescriptor.symbolicTraits
                let newTraits = traits.contains(trait) ? traits.subtracting(trait) : traits.union(trait)
                attrs[.font] = systemFont(preserving: newTraits)
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
            let normalizedBase = systemFont(
                ofSize: base.pointSize,
                preservingTraitsFrom: base
            )
            let currentTraits = normalizedBase.fontDescriptor.symbolicTraits
            let newTraits = allHave ? currentTraits.subtracting(trait) : currentTraits.union(trait)
            storage.addAttribute(
                .font,
                value: systemFont(ofSize: base.pointSize, preserving: newTraits),
                range: range
            )
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

    func selectedPlainText(for range: NSRange) -> String {
        guard let storage = textStorage, range.length > 0,
              NSMaxRange(range) <= storage.length else { return "" }
        let nsString = storage.string as NSString
        var result = ""
        var location = range.location
        let end = NSMaxRange(range)

        while location < end {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attrs = storage.attributes(at: location, effectiveRange: &effectiveRange)
            let clampedEnd = min(NSMaxRange(effectiveRange), end)

            if let todo = attrs[.attachment] as? TodoAttachment {
                result += todo.isChecked ? "☑" : "☐"
                location = NSMaxRange(effectiveRange)
                if location < end, nsString.character(at: location) == 32 {
                    location += 1
                }
            } else {
                let clampedStart = max(effectiveRange.location, location)
                result += nsString.substring(with: NSRange(location: clampedStart, length: clampedEnd - clampedStart))
                location = clampedEnd
            }
        }
        return result
    }

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

    // MARK: - Apple Notes export

    func markdownContent(title: String) -> String {
        let content: NSAttributedString
        if let textStorage {
            content = textStorage
        } else {
            content = NSAttributedString(string: string)
        }
        return NoteMarkdown.export(
            content,
            title: title,
            indentWidth: ListIndent.width
        )
    }

    func htmlContent() -> String {
        guard let storage = textStorage else { return plainTextContent() }
        let mutable = mutableCopyReplacingTodoAttachments(in: storage) { isChecked, _ in
            let symbol = isChecked ? "☑" : "☐"
            return NSAttributedString(string: symbol, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: editorTextColor
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
        let normalizedStorage = NSMutableAttributedString(attributedString: storage)
        let normalizedRange = NSRange(location: 0, length: normalizedStorage.length)
        normalizedStorage.removeAttribute(.baselineOffset, range: normalizedRange)
        normalizedStorage.removeAttribute(NSAttributedString.Key("NSSuperscript"), range: normalizedRange)
        normalizeParagraphSpacing(
            in: normalizedStorage,
            range: normalizedRange
        )
        let mutable = mutableCopyReplacingTodoAttachments(in: normalizedStorage) { isChecked, paraStyle in
            let marker = isChecked ? "\u{2611}" : "\u{2610}"
            return NSAttributedString(string: marker, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: editorTextColor,
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
        in storage: NSAttributedString,
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
            updateDefaultTypingAttributes()
            needsDisplay = true
            return
        }

        let mutable = NSMutableAttributedString(attributedString: atStr)
        let fullRange = NSRange(location: 0, length: mutable.length)

        // Normalize all fonts to system font, preserving bold/italic traits
        mutable.enumerateAttribute(.font, in: fullRange) { val, range, _ in
            guard let font = val as? NSFont else { return }
            mutable.addAttribute(
                .font,
                value: systemFont(preservingTraitsFrom: font),
                range: range
            )
        }

        // Normalize foreground colors to adaptive textColor; re-apply linkColor to link ranges
        mutable.removeAttribute(.foregroundColor, range: fullRange)
        mutable.addAttribute(.foregroundColor, value: editorTextColor, range: fullRange)
        mutable.removeAttribute(.baselineOffset, range: fullRange)
        mutable.removeAttribute(NSAttributedString.Key("NSSuperscript"), range: fullRange)
        mutable.enumerateAttribute(.link, in: fullRange) { val, range, _ in
            if val != nil {
                mutable.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
            }
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

        canonicalizeExternalBulletLists(in: mutable, range: NSRange(location: 0, length: mutable.length))
        normalizeParagraphSpacing(in: mutable, range: NSRange(location: 0, length: mutable.length))
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
        let strikethroughItem = sub.addItem(withTitle: "Strikethrough", action: #selector(strikethroughAction(_:)), keyEquivalent: "")
        sub.addItem(.separator())
        let linkItem = sub.addItem(withTitle: "Link…", action: #selector(linkAction(_:)), keyEquivalent: "")

        for item in [boldItem, italicItem, underlineItem, strikethroughItem, linkItem] {
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
            #selector(underlineAction(_:)),
            #selector(strikethroughAction(_:))
        ]
        if let action = item.action, formattingActions.contains(action) {
            // With no selection these toggle `typingAttributes` for whatever is
            // typed next — the same thing ⌘B does — so they stay enabled.
            return isEditable
        }
        return super.validateMenuItem(item)
    }

    // Internal rather than private so the Format menu in `MainMenu.swift` can
    // build selectors for them; they are reached through the responder chain, so
    // AppKit enables the menu items only while the editor is focused.
    @objc func boldAction(_ sender: Any?)      { applyBold() }
    @objc func italicAction(_ sender: Any?)    { applyItalic() }
    @objc func underlineAction(_ sender: Any?) { applyUnderline() }
    @objc func strikethroughAction(_ sender: Any?) { applyStrikethrough() }
    @objc func bulletListAction(_ sender: Any?) { applyBullet() }
    @objc func todoListAction(_ sender: Any?)   { applyTodo() }
    @objc func linkAction(_ sender: Any?) {
        buoyDelegate?.textViewRequestShowLinkDialog(context: linkEditingContext())
    }
}
