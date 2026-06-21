import AppKit

final class TextViewCoordinator: NSObject, NSTextViewDelegate {
    var onHeightChange: ((CGFloat) -> Void)?
    var onSelectionChange: ((String) -> Void)?
    var onContentChange: ((Data) -> Void)?
    var currentNoteID: String?
    private(set) var isLoadingContent = false
    // Last reported document length. The window only auto-grows when the document
    // gets *longer* (typing, paste, adding a list item) — never for attribute-only
    // edits like bold/italic/underline/strikethrough, which leave length unchanged.
    private var lastTextLength = 0

    func setLoadingContent(_ loading: Bool) {
        isLoadingContent = loading
    }

    /// Resyncs the baseline length after a note load/switch so the first real edit
    /// on the new note isn't mis-classified against the previous note's length.
    func syncTextLength(_ length: Int) {
        lastTextLength = length
    }

    func textDidChange(_ notification: Notification) {
        guard !isLoadingContent,
              let tv = notification.object as? BuoyTextView else { return }
        if let rtf = tv.rtfContent() {
            onContentChange?(rtf)
        }
        let newLength = (tv.string as NSString).length
        let grew = newLength > lastTextLength
        lastTextLength = newLength
        // Pure formatting (length unchanged) must not resize the window — the user
        // expands it manually; only longer content stretches it downward.
        guard grew else { return }
        let h = tv.measureContentHeight()
        DispatchQueue.main.async { [weak self] in
            self?.onHeightChange?(h)
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let tv = notification.object as? BuoyTextView else { return }
        onSelectionChange?(tv.selectedPlainText(for: tv.selectedRange()))
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init)
        if let url { NSWorkspace.shared.open(url) }
        return true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool { false }
}
