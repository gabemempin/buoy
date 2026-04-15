import AppKit
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

// MARK: - NotesTableViewWrapper

struct NotesTableViewWrapper: NSViewRepresentable {
    var notes: [Note]
    var currentNoteID: String?
    var onSelect: (Note) -> Void
    var onDelete: (Note) -> Void

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
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none // Visual selection handled by NoteRow

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
                onSelect: { [weak self] in
                    self?.parent.onSelect(note)
                },
                onDelete: { [weak self] in
                    self?.parent.onDelete(note)
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
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tv = tableView else { return }
            let row = tv.selectedRow
            if row >= 0 && row < notes.count {
                let selectedNote = notes[row]
                parent.onSelect(selectedNote)
                tv.deselectRow(row) // Instantly revert table selection, keep visual state in SwiftUI
            }
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
