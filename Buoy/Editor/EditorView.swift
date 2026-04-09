import SwiftUI
import AppKit

/// NSScrollView that never initiates window drag, so text selection works without moving the window.
private final class DragBlockingScrollView: NSScrollView {
    override var mouseDownCanMoveWindow: Bool { false }
    override var needsPanelToBecomeKey: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        syncDocumentViewGeometry()
    }

    override func tile() {
        super.tile()
        syncDocumentViewGeometry()
    }

    private func syncDocumentViewGeometry() {
        guard let textView = documentView as? BuoyTextView else { return }

        let contentSize = self.contentSize
        guard contentSize.width > 0, contentSize.height > 0 else { return }

        let targetHeight = max(textView.frame.height, contentSize.height)
        if abs(textView.frame.width - contentSize.width) > 0.5
            || abs(textView.frame.height - targetHeight) > 0.5 {
            textView.frame = NSRect(origin: .zero, size: NSSize(width: contentSize.width, height: targetHeight))
        }

        let targetMinSize = NSSize(width: 0, height: contentSize.height)
        if textView.minSize != targetMinSize {
            textView.minSize = targetMinSize
        }

        let targetContainerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        if textView.textContainer?.containerSize != targetContainerSize {
            textView.textContainer?.containerSize = targetContainerSize
        }
        textView.textContainer?.widthTracksTextView = true
    }
}

struct EditorView: NSViewRepresentable {
    var rtfData: Data
    var fontSize: CGFloat
    var usesDarkAppearance: Bool
    var noteID: String
    var placeholder: String = "Start typing… (⌘← ⌘→ to navigate notes)"
    var onHeightChange: ((CGFloat) -> Void)?
    var onNoteSwitch: ((CGFloat) -> Void)?
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
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.autoresizesSubviews = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        let contentSize = scrollView.contentSize
        let initialWidth = max(
            contentSize.width,
            PanelLayoutMetrics.minimumContentWidth - (PanelLayoutMetrics.windowPadding * 2)
        )
        let initialHeight = max(contentSize.height, PanelLayoutMetrics.editorMinimumHeight)

        let textView = BuoyTextView(
            frame: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight)
        )
        textView.fontSize = fontSize
        textView.usesDarkAppearance = usesDarkAppearance
        textView.minSize = NSSize(width: 0, height: initialHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: initialWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.buoyDelegate = context.coordinator

        scrollView.documentView = textView
        scrollView.layoutSubtreeIfNeeded()
        context.coordinator.currentNoteID = noteID
        textViewRef?(textView)

        context.coordinator.setLoadingContent(true)
        textView.loadRTF(rtfData)
        context.coordinator.setLoadingContent(false)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? BuoyTextView else { return }

        scrollView.layoutSubtreeIfNeeded()
        textViewRef?(textView)

        if textView.fontSize != fontSize {
            textView.fontSize = fontSize
        }

        if textView.usesDarkAppearance != usesDarkAppearance {
            textView.usesDarkAppearance = usesDarkAppearance
        }

        if textView.placeholderString != placeholder {
            textView.placeholderString = placeholder
        }

        if context.coordinator.currentNoteID != noteID {
            context.coordinator.currentNoteID = noteID
            context.coordinator.setLoadingContent(true)
            textView.loadRTF(rtfData)
            context.coordinator.setLoadingContent(false)
            let h = textView.measureContentHeight()
            onNoteSwitch?(h)
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
