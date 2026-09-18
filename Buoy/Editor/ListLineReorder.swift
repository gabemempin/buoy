import AppKit

/// A maximal run of consecutive list paragraphs (todo or bullet) that a drag may reorder within.
struct ListBlock {
    let paragraphs: [NSRange]
    let range: NSRange
}

/// Thin horizontal bar shown at a candidate drop boundary while dragging a list marker.
final class ListInsertionIndicatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = BuoyTheme.current.accentNSColor.cgColor
        layer?.cornerRadius = 1
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Drives the drag-to-reorder gesture for list lines (todo checkboxes / bullets) inside a
/// `BuoyTextView`. Started by `BuoyTextView` once a mouse-down on a marker glyph has moved
/// past a small threshold; this controller owns the drop-indicator UI and the event-tracking
/// loop, and reports back the chosen drop boundary (or nil if cancelled).
final class ListReorderController {
    private weak var textView: BuoyTextView?

    private lazy var indicatorView: ListInsertionIndicatorView = {
        let v = ListInsertionIndicatorView(frame: .zero)
        v.isHidden = true
        return v
    }()

    private var indicatorInstalled = false

    init(textView: BuoyTextView) {
        self.textView = textView
    }

    private func installIndicatorIfNeeded() {
        guard !indicatorInstalled, let tv = textView else { return }
        tv.addSubview(indicatorView)
        indicatorInstalled = true
    }

    /// Runs the drag-tracking loop for reordering `block.paragraphs[sourceIndex]`. `firstDragEvent`
    /// is the `.leftMouseDragged` event that crossed the initiation threshold. Returns the target
    /// insertion boundary (0...paragraphs.count) to move to, or nil if the drag was cancelled /
    /// ended without a valid new position.
    func runReorderDragLoop(block: ListBlock, sourceIndex: Int, firstDragEvent: NSEvent) -> Int? {
        guard let tv = textView, let layout = tv.layoutManager, let container = tv.textContainer,
              let window = tv.window else { return nil }
        installIndicatorIfNeeded()

        var boundaryYs: [CGFloat] = []
        for para in block.paragraphs {
            let glyphRange = layout.glyphRange(forCharacterRange: para, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
            boundaryYs.append(rect.minY + tv.textContainerInset.height)
        }
        if let lastPara = block.paragraphs.last {
            let glyphRange = layout.glyphRange(forCharacterRange: lastPara, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
            boundaryYs.append(rect.maxY + tv.textContainerInset.height)
        }
        let blockMinY = boundaryYs.min() ?? 0
        let blockMaxY = boundaryYs.max() ?? 0

        NSCursor.closedHand.push()
        let dimColor = tv.currentEditorTextColor.withAlphaComponent(0.3)
        layout.addTemporaryAttribute(.foregroundColor, value: dimColor, forCharacterRange: block.paragraphs[sourceIndex])

        var targetBoundary: Int?
        indicatorView.isHidden = true

        func process(_ event: NSEvent) -> Bool {
            switch event.type {
            case .keyDown:
                if event.keyCode == 53 { // Escape
                    targetBoundary = nil
                    return true
                }
                return false
            case .leftMouseDragged:
                tv.autoscroll(with: event)
                let p = tv.convert(event.locationInWindow, from: nil)
                if p.y >= blockMinY - 24 && p.y <= blockMaxY + 24 {
                    let nearest = boundaryYs.indices.min(by: {
                        abs(boundaryYs[$0] - p.y) < abs(boundaryYs[$1] - p.y)
                    })
                    if let nearest, nearest != sourceIndex, nearest != sourceIndex + 1 {
                        targetBoundary = nearest
                        indicatorView.isHidden = false
                        indicatorView.frame = NSRect(
                            x: 9,
                            y: boundaryYs[nearest] - 1,
                            width: max(0, tv.bounds.width - 18),
                            height: 2
                        )
                    } else {
                        targetBoundary = nil
                        indicatorView.isHidden = true
                    }
                } else {
                    targetBoundary = nil
                    indicatorView.isHidden = true
                }
                return false
            case .leftMouseUp:
                return true
            default:
                return false
            }
        }

        var done = process(firstDragEvent)
        while !done {
            guard let event = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }
            done = process(event)
        }

        NSCursor.pop()
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: block.paragraphs[sourceIndex])
        indicatorView.isHidden = true

        return targetBoundary
    }
}
