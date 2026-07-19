import AppKit
import QuartzCore
import SwiftUI

// MARK: - SearchFieldWrapper

struct SearchFieldWrapper: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        searchField.focusRingType = .none
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.controlSize = .small
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchFieldWrapper

        init(_ parent: SearchFieldWrapper) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSSearchField {
                parent.text = field.stringValue
            }
        }
    }
}

// MARK: - ThemePickerWrapper

struct ThemePickerWrapper: NSViewRepresentable {
    @Binding var selection: AppTheme

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: ["Auto", "Light", "Dark"],
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.onChange(_:))
        )
        control.segmentStyle = .roundRect
        control.controlSize = .small
        return control
    }

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
        switch selection {
        case .system: nsView.selectedSegment = 0
        case .light: nsView.selectedSegment = 1
        case .dark: nsView.selectedSegment = 2
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject {
        var parent: ThemePickerWrapper

        init(_ parent: ThemePickerWrapper) {
            self.parent = parent
        }

        @objc func onChange(_ sender: NSSegmentedControl) {
            switch sender.selectedSegment {
            case 0: parent.selection = .system
            case 1: parent.selection = .light
            case 2: parent.selection = .dark
            default: break
            }
        }
    }
}

// MARK: - NoSeparatorRowView

private final class NoSeparatorRowView: NSTableRowView {
    override func drawSeparator(in dirtyRect: NSRect) {}
}

// MARK: - NoteRowDragHandle

/// AppKit drag source for reordering pinned note rows. SwiftUI's `.onDrag` inside an
/// NSHostingView table cell produces no visible drag preview, so this view starts a real
/// NSDraggingSession with a snapshot of the enclosing row — the row visibly follows the
/// cursor. It covers the row's title area, so it also forwards plain clicks to `onSelect`
/// (the SwiftUI tap gesture underneath never sees them).
struct NoteRowDragHandle: NSViewRepresentable {
    var noteID: String
    var onSelect: () -> Void

    func makeNSView(context: Context) -> DragHandleNSView {
        DragHandleNSView(
            noteID: noteID,
            onSelect: onSelect
        )
    }

    func updateNSView(_ nsView: DragHandleNSView, context: Context) {
        nsView.noteID = noteID
        nsView.onSelect = onSelect
    }

    final class DragHandleNSView: NSView, NSDraggingSource {
        var noteID: String
        var onSelect: () -> Void
        private weak var sourceRowView: NSTableRowView?
        private var isLifted = false
        private static let dragThreshold: CGFloat = 3
        private static let shadowPadding: CGFloat = 8
        private static let longPressDelay: TimeInterval = 0.16

        init(
            noteID: String,
            onSelect: @escaping () -> Void
        ) {
            self.noteID = noteID
            self.onSelect = onSelect
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else {
                onSelect()
                return
            }

            let pressLocation = event.locationInWindow
            let liftDeadline = Date(
                timeIntervalSinceNow: Self.longPressDelay
            )
            while true {
                let next = window.nextEvent(
                    matching: [.leftMouseDragged, .leftMouseUp],
                    until: isLifted ? .distantFuture : liftDeadline,
                    inMode: .eventTracking,
                    dequeue: true
                )
                guard let next else {
                    setLifted(true)
                    continue
                }

                switch next.type {
                case .leftMouseUp:
                    setLifted(false)
                    onSelect()
                    return
                case .leftMouseDragged:
                    let dx = next.locationInWindow.x - pressLocation.x
                    let dy = next.locationInWindow.y - pressLocation.y
                    guard hypot(dx, dy) >= Self.dragThreshold else { continue }
                    setLifted(true)
                    startDragging(with: next)
                    return
                default:
                    break
                }
            }
        }

        private func startDragging(with event: NSEvent) {
            let item = NSPasteboardItem()
            item.setString(noteID, forType: NotesTableViewWrapper.noteRowPasteboardType)
            let dragItem = NSDraggingItem(pasteboardWriter: item)

            guard let rowView = sourceRowView ?? enclosingRowView() else {
                setLifted(false)
                return
            }
            sourceRowView = rowView

            let image = liftedImage(for: rowView)
            let rowFrame = convert(rowView.bounds, from: rowView)
            let dragFrame = rowFrame.insetBy(
                dx: -Self.shadowPadding,
                dy: -Self.shadowPadding
            )
            dragItem.setDraggingFrame(dragFrame, contents: image)

            let session = beginDraggingSession(with: [dragItem], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = false
        }

        private func setLifted(_ lifted: Bool) {
            guard lifted != isLifted else { return }
            isLifted = lifted
            if lifted, sourceRowView == nil {
                sourceRowView = enclosingRowView()
            }
            guard let rowView = sourceRowView else { return }

            rowView.wantsLayer = true
            guard let layer = rowView.layer else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(lifted ? 0.08 : 0.12)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(name: .easeOut)
            )
            layer.transform = lifted
                ? CATransform3DMakeScale(1.015, 1.015, 1)
                : CATransform3DIdentity
            layer.backgroundColor = lifted
                ? NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
                : NSColor.clear.cgColor
            layer.cornerRadius = lifted ? 7 : 0
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = lifted ? 0.14 : 0
            layer.shadowRadius = lifted ? 5 : 0
            layer.shadowOffset = lifted
                ? CGSize(width: 0, height: -2)
                : .zero
            layer.shadowPath = lifted
                ? CGPath(
                    roundedRect: rowView.bounds,
                    cornerWidth: 7,
                    cornerHeight: 7,
                    transform: nil
                )
                : nil
            layer.zPosition = lifted ? 10 : 0
            layer.masksToBounds = false
            CATransaction.commit()
        }

        private func enclosingRowView() -> NSTableRowView? {
            var probe: NSView? = superview
            while let view = probe {
                if let rowView = view as? NSTableRowView {
                    return rowView
                }
                probe = view.superview
            }
            return nil
        }

        private func liftedImage(for rowView: NSTableRowView) -> NSImage {
            let snapshot = NSImage(size: rowView.bounds.size)
            if let representation = rowView.bitmapImageRepForCachingDisplay(in: rowView.bounds) {
                rowView.cacheDisplay(in: rowView.bounds, to: representation)
                snapshot.addRepresentation(representation)
            }

            let padding = Self.shadowPadding
            let imageSize = NSSize(
                width: rowView.bounds.width + padding * 2,
                height: rowView.bounds.height + padding * 2
            )
            let image = NSImage(size: imageSize)
            image.lockFocus()

            let cardRect = NSRect(
                x: padding,
                y: padding,
                width: rowView.bounds.width,
                height: rowView.bounds.height
            )
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
            NSBezierPath(
                roundedRect: cardRect,
                xRadius: 7,
                yRadius: 7
            ).fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(
                roundedRect: cardRect,
                xRadius: 7,
                yRadius: 7
            ).addClip()
            snapshot.draw(in: cardRect)
            NSGraphicsContext.restoreGraphicsState()
            image.unlockFocus()
            return image
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }

        func draggingSession(
            _ session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint
        ) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                sourceRowView?.animator().alphaValue = 0.28
            }
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            if let rowView = sourceRowView {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    rowView.animator().alphaValue = 1
                }
            }
            setLifted(false)
            sourceRowView = nil
        }
    }
}

// MARK: - NotesTableViewWrapper

struct NotesTableViewWrapper: NSViewRepresentable {
    static let noteRowPasteboardType = NSPasteboard.PasteboardType(
        "GabeMempin.Buoy.note-row"
    )

    var notes: [Note]
    var currentNoteID: String?
    var onSelect: (Note) -> Void
    var onDelete: (Note) -> Void
    var onTogglePin: (Note) -> Void
    var onReorderPinned: ([String]) -> Void
    var allowsPinnedReordering: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 30 // Approx height of NoteRow
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = []
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none // Visual selection handled by NoteRow
        tableView.draggingDestinationFeedbackStyle = .gap
        tableView.registerForDraggedTypes([Self.noteRowPasteboardType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("NoteColumn"))
        tableView.addTableColumn(column)
        
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        
        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        
        if coordinator.notes.map({ $0.id }) != notes.map({ $0.id }) {
            coordinator.notes = notes
            coordinator.tableView?.reloadData()
        } else {
            // Notes array hasn't structurally changed, but properties (like title, or selection) might have.
            // A simple reload is extremely fast for our small note list.
            coordinator.notes = notes
            coordinator.tableView?.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NotesTableViewWrapper
        var notes: [Note] = []
        weak var tableView: NSTableView?

        init(_ parent: NotesTableViewWrapper) {
            self.parent = parent
            self.notes = parent.notes
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            return notes.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < notes.count else { return nil }
            let note = notes[row]
            let isActive = note.id == parent.currentNoteID
            
            let identifier = NSUserInterfaceItemIdentifier("NoteCell")
            let view = tableView.makeView(withIdentifier: identifier, owner: self) as? NSHostingView<AnyView>

            let rowView = NoteRow(
                note: note,
                isActive: isActive,
                dragNoteID: parent.allowsPinnedReordering && note.isPinned ? note.id : nil,
                onSelect: { [weak self] in
                    self?.parent.onSelect(note)
                },
                onDelete: { [weak self] in
                    self?.parent.onDelete(note)
                },
                onTogglePin: { [weak self] in
                    self?.parent.onTogglePin(note)
                }
            )
            
            if let hostingView = view {
                hostingView.rootView = AnyView(rowView)
                return hostingView
            } else {
                let newHostingView = NSHostingView(rootView: AnyView(rowView))
                newHostingView.identifier = identifier
                return newHostingView
            }
        }
        
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            return NoSeparatorRowView()
        }

        func tableView(
            _ tableView: NSTableView,
            pasteboardWriterForRow row: Int
        ) -> NSPasteboardWriting? {
            guard parent.allowsPinnedReordering,
                  row >= 0,
                  row < notes.count,
                  notes[row].isPinned
            else { return nil }

            let item = NSPasteboardItem()
            item.setString(notes[row].id, forType: NotesTableViewWrapper.noteRowPasteboardType)
            return item
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard parent.allowsPinnedReordering,
                  draggedNoteID(from: info) != nil,
                  row >= 0,
                  row <= pinnedNoteCount
            else { return [] }

            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            guard parent.allowsPinnedReordering,
                  let draggedID = draggedNoteID(from: info),
                  let sourceIndex = notes.firstIndex(where: { $0.id == draggedID }),
                  sourceIndex < pinnedNoteCount,
                  row >= 0,
                  row <= pinnedNoteCount
            else { return false }

            var reorderedPinned = Array(notes.prefix(pinnedNoteCount))
            let movedNote = reorderedPinned.remove(at: sourceIndex)
            var destinationIndex = row
            if sourceIndex < destinationIndex {
                destinationIndex -= 1
            }
            destinationIndex = min(max(destinationIndex, 0), reorderedPinned.count)

            guard destinationIndex != sourceIndex else { return false }

            reorderedPinned.insert(movedNote, at: destinationIndex)
            notes = reorderedPinned + Array(notes.dropFirst(pinnedNoteCount))
            tableView.reloadData()
            parent.onReorderPinned(reorderedPinned.map(\.id))
            return true
        }

        private var pinnedNoteCount: Int {
            notes.prefix(while: \.isPinned).count
        }

        private func draggedNoteID(from info: NSDraggingInfo) -> String? {
            info.draggingPasteboard.string(
                forType: NotesTableViewWrapper.noteRowPasteboardType
            )
        }

        func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
            guard edge == .trailing else { return [] }
            let deleteAction = NSTableViewRowAction(style: .destructive, title: "Delete") { [weak self] action, rowIndex in
                guard let self = self, rowIndex < self.notes.count else { return }
                self.parent.onDelete(self.notes[rowIndex])
            }
            return [deleteAction]
        }
    }
}
