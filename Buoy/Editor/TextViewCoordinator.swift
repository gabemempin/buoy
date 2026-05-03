import AppKit

final class TextViewCoordinator: NSObject, NSTextViewDelegate {
    var onHeightChange: ((CGFloat) -> Void)?
    var onSelectionChange: ((String) -> Void)?
    var onContentChange: ((Data) -> Void)?
    var currentNoteID: String?
    private(set) var isLoadingContent = false

    func setLoadingContent(_ loading: Bool) {
        isLoadingContent = loading
    }

    func textDidChange(_ notification: Notification) {
        guard !isLoadingContent,
              let tv = notification.object as? BuoyTextView else { return }
        if let rtf = tv.rtfContent() {
            onContentChange?(rtf)
        }
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
