import AppKit

/// NSTextViewDelegate that bridges FloatNotesTextView events upward via callbacks.
final class TextViewCoordinator: NSObject, NSTextViewDelegate {
    var onHeightChange: ((CGFloat) -> Void)?
    var onSelectionChange: ((NSRange) -> Void)?
    var onContentChange: ((Data) -> Void)?
    var currentNoteID: String?
    private(set) var isLoadingContent = false

    func setLoadingContent(_ loading: Bool) {
        isLoadingContent = loading
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard !isLoadingContent,
              let tv = notification.object as? FloatNotesTextView else { return }
        if let rtf = tv.rtfContent() {
            onContentChange?(rtf)
        }
        let h = tv.measureContentHeight()
        DispatchQueue.main.async { [weak self] in
            self?.onHeightChange?(h)
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let tv = notification.object as? FloatNotesTextView else { return }
        onSelectionChange?(tv.selectedRange())
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url: URL?
        if let u = link as? URL { url = u }
        else if let s = link as? String { url = URL(string: s) }
        else { url = nil }
        if let url { NSWorkspace.shared.open(url) }
        return true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        return false
    }
}
