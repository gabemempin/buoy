import SwiftUI
import AppKit

/// NSScrollView that never initiates window drag, so text selection works without moving the window.
private final class DragBlockingScrollView: NSScrollView {
    override var mouseDownCanMoveWindow: Bool { false }
}

struct EditorView: NSViewRepresentable {
    var rtfData: Data
    var fontSize: CGFloat
    var noteID: String
    var onHeightChange: ((CGFloat) -> Void)?
    var onSelectionChange: ((NSRange) -> Void)?
    var onContentChange: ((Data) -> Void)?
    var textViewRef: ((BuoyTextView) -> Void)?

    func makeCoordinator() -> TextViewCoordinator {
        let c = TextViewCoordinator()
        c.onHeightChange = onHeightChange
        c.onSelectionChange = onSelectionChange
        c.onContentChange = onContentChange
        return c
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = DragBlockingScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        let textView = BuoyTextView(frame: .zero)
        textView.fontSize = fontSize
        textView.delegate = context.coordinator
        textView.buoyDelegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.currentNoteID = noteID
        textViewRef?(textView)

        context.coordinator.setLoadingContent(true)
        textView.loadRTF(rtfData)
        context.coordinator.setLoadingContent(false)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? BuoyTextView else { return }

        textViewRef?(textView)

        if textView.fontSize != fontSize {
            textView.fontSize = fontSize
        }

        if context.coordinator.currentNoteID != noteID {
            context.coordinator.currentNoteID = noteID
            context.coordinator.setLoadingContent(true)
            textView.loadRTF(rtfData)
            context.coordinator.setLoadingContent(false)
            let h = textView.measureContentHeight()
            onHeightChange?(h)
        }

        context.coordinator.onHeightChange = onHeightChange
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onContentChange = onContentChange
    }
}

// MARK: - Coordinator BuoyTextViewDelegate conformance

extension TextViewCoordinator: BuoyTextViewDelegate {
    func textViewDidChange(_ textView: BuoyTextView) {
        guard !isLoadingContent else { return }
        if let rtf = textView.rtfContent() {
            onContentChange?(rtf)
        }
    }

    func textViewHeightDidChange(_ height: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            self?.onHeightChange?(height)
        }
    }

    func textViewSelectionDidChange(_ textView: BuoyTextView) {
        onSelectionChange?(textView.selectedRange())
    }

    func textViewRequestShowLinkDialog(selectedText: String) {
        NotificationCenter.default.post(name: .showLinkDialog, object: selectedText)
    }
}

extension Notification.Name {
    static let showLinkDialog = Notification.Name("BuoyShowLinkDialog")
}
