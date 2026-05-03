import SwiftUI
import AppKit

/// NSScrollView that never initiates window drag, so text selection works without moving the window.
private final class DragBlockingScrollView: NSScrollView {
    override var mouseDownCanMoveWindow: Bool { false }
    override var needsPanelToBecomeKey: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private var accumulatedDeltaX: CGFloat = 0
    private var isTrackingSwipe = false

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began {
            // Initiate tracking if the horizontal intent dominates vertical intent
            isTrackingSwipe = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            accumulatedDeltaX = 0
        }

        if isTrackingSwipe, event.phase == .changed || event.phase == .ended {
            accumulatedDeltaX += event.scrollingDeltaX

            // Threshold is ~50pt for a clean trigger
            if accumulatedDeltaX > 50 {
                NotificationCenter.default.post(name: .buoyPreviousNote, object: nil)
                isTrackingSwipe = false
                accumulatedDeltaX = 0
            } else if accumulatedDeltaX < -50 {
                NotificationCenter.default.post(name: .buoyNextNote, object: nil)
                isTrackingSwipe = false
                accumulatedDeltaX = 0
            }
        }

        if !isTrackingSwipe {
            super.scrollWheel(with: event)
        }
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
    var onSelectionChange: ((String) -> Void)?
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
        // Start hidden so the scroller doesn't flash during the slide-in transition.
        // Re-enabled after the spring animation (~0.3s response) settles.
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
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

        // Re-enable the scroller after the slide-in transition finishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            scrollView.hasVerticalScroller = true
        }

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
            // Temporarily hide the scroller so the content swap doesn't flash it.
            scrollView.hasVerticalScroller = false
            context.coordinator.setLoadingContent(true)
            textView.loadRTF(rtfData)
            context.coordinator.setLoadingContent(false)
            let h = textView.measureContentHeight()
            onNoteSwitch?(h)
            // Re-enable after AppKit's scroller-flash window has passed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                scrollView.hasVerticalScroller = true
            }
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
        onSelectionChange?(textView.selectedPlainText(for: textView.selectedRange()))
    }

    func textViewRequestShowLinkDialog(selectedText: String) {
        NotificationCenter.default.post(name: .showLinkDialog, object: selectedText)
    }
}

extension Notification.Name {
    static let showLinkDialog = Notification.Name("BuoyShowLinkDialog")
}
