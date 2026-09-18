import AppKit
import SwiftUI

// MARK: - Actions

/// Everything the All Notes list can ask the app to do. Grouped into one value
/// so the wrapper doesn't carry a dozen loose closure properties.
struct AllNotesActions {
    var selectNote: (Note) -> Void
    var deleteNote: (Note) -> Void
    var togglePin: (Note) -> Void
    var reorderPinned: ([String]) -> Void
    var reorderFolders: ([String]) -> Void
    /// `(noteID, folderID, index)` — `nil` index appends.
    var fileNote: (String, String, Int?) -> Void
    var unfileNote: (String) -> Void
    var reorderInFolder: (String, [String]) -> Void
    var renameFolder: (String, String) -> Void
    /// Rename abandoned. Takes the id so a folder that was created purely to
    /// be named can be removed again rather than left as "New Folder".
    var cancelRenameFolder: (String) -> Void
    var requestDeleteFolder: (Folder) -> Void
    var setFolderExpanded: (String, Bool) -> Void
    /// Puts a folder row into inline-rename mode, or clears it with `nil`.
    var setRenamingFolder: (String?) -> Void
}

// MARK: - AllNotesNode

/// One row in the All Notes outline.
///
/// `NSOutlineView` tracks items by identity, so these must be the *same*
/// object across rebuilds — the coordinator caches them by `key`. One note can
/// appear as three separate rows (pinned band, folder child, All Notes), which
/// is exactly why the key carries the placement rather than just the note id.
final class AllNotesNode: NSObject {
    enum Kind {
        case note(id: String)
        case folder(id: String)
        case divider
    }

    enum Placement: Equatable {
        case pinned
        case folderRow
        case folderChild(folderID: String)
        case allNotes
        case separator
    }

    let key: String
    let kind: Kind
    let placement: Placement
    var children: [AllNotesNode] = []

    init(key: String, kind: Kind, placement: Placement) {
        self.key = key
        self.kind = kind
        self.placement = placement
        super.init()
    }

    var noteID: String? {
        if case .note(let id) = kind { return id }
        return nil
    }

    var folderID: String? {
        if case .folder(let id) = kind { return id }
        return nil
    }

    var isDivider: Bool {
        if case .divider = kind { return true }
        return false
    }

    /// The folder this node is a child of, if any.
    var parentFolderID: String? {
        if case .folderChild(let id) = placement { return id }
        return nil
    }

    override var hash: Int { key.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? AllNotesNode)?.key == key
    }

    static func pinnedKey(_ noteID: String) -> String { "pin:\(noteID)" }
    static func allNotesKey(_ noteID: String) -> String { "all:\(noteID)" }
    static func folderKey(_ folderID: String) -> String { "fold:\(folderID)" }
    static func childKey(folderID: String, noteID: String) -> String { "kid:\(folderID):\(noteID)" }
}

/// The flattened row tree plus the top-level index bands each section occupies.
/// Drop validation is entirely a question of "which band is this insertion
/// point in", so the ranges are computed once at build time.
struct AllNotesTree {
    var topLevel: [AllNotesNode] = []
    var pinnedRange: Range<Int> = 0..<0
    var folderRange: Range<Int> = 0..<0
    var allNotesRange: Range<Int> = 0..<0
    var signature: [String] = []
}

// MARK: - PassthroughHostingView

/// Hosts a SwiftUI row but stays transparent to the mouse except over the
/// regions SwiftUI reported as interactive.
///
/// This is what lets AppKit own selection and dragging while the row is still
/// drawn, themed and labelled in SwiftUI. Previously the row's SwiftUI content
/// swallowed every `mouseDown`, which is why reordering needed a second,
/// separate AppKit drag source bolted under the title — the thing that made
/// dragging feel like two different features. The regions are published by the
/// row itself through `InteractiveRegionKey`, so they stay correct when the
/// layout changes instead of being guessed from hard-coded rects.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRegions: [CGRect] = []

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        // SwiftUI reports regions with a top-left origin; NSView may not be
        // flipped, so normalise before testing.
        let probe = isFlipped
            ? local
            : CGPoint(x: local.x, y: bounds.height - local.y)
        let isInteractive = interactiveRegions.contains {
            $0.insetBy(dx: -2, dy: -2).contains(probe)
        }
        guard isInteractive else { return nil }
        return super.hitTest(point)
    }
}

/// Collects the frames of a row's interactive controls in the row's own
/// coordinate space.
struct InteractiveRegionKey: PreferenceKey {
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Marks this view as clickable so `PassthroughHostingView` lets the mouse
    /// reach it. Every button inside an All Notes row needs this.
    func interactiveRegion(in space: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: InteractiveRegionKey.self,
                    value: [proxy.frame(in: .named(space))]
                )
            }
        )
    }
}

// MARK: - Row and outline views

/// Draws no separator (the panel supplies its own dividers) and owns hover
/// tracking for its row.
///
/// Hover lives here rather than in SwiftUI's `onHover` because the row's
/// content is not hit-testable: AppKit is the only layer that reliably knows
/// the pointer is over this row. It also means hover state cannot survive into
/// a different note when a cell view is reused.
final class NotesRowView: NSTableRowView {
    var onHoverChange: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func drawSeparator(in dirtyRect: NSRect) {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}

/// Reports plain clicks that did not turn into a drag.
///
/// `super.mouseDown` runs AppKit's own tracking loop, which is what starts the
/// drag. The delegate flips `didStartDragDuringTracking` when a session begins,
/// so anything that reaches the end of tracking without one is a click.
final class NotesOutlineView: NSOutlineView {
    var onRowClicked: ((Int) -> Void)?
    var didStartDragDuringTracking = false

    /// How far the pointer may travel during a press and still count as a
    /// click rather than a drag.
    private static let clickSlop: CGFloat = 4

    override func mouseDown(with event: NSEvent) {
        let clickedRow = row(at: convert(event.locationInWindow, from: nil))
        let pressLocation = NSEvent.mouseLocation
        didStartDragDuringTracking = false
        super.mouseDown(with: event)

        // `didStartDragDuringTracking` alone is not enough. AppKit can begin
        // the session after `super.mouseDown` has already returned, so the flag
        // is still false at this point and a *drag* would be reported as a
        // click — which selected the dragged note and closed the whole panel
        // out from under the drag. Measuring how far the pointer actually
        // moved does not depend on when the callback lands.
        let released = NSEvent.mouseLocation
        let travelled = hypot(
            released.x - pressLocation.x,
            released.y - pressLocation.y
        )

        guard !didStartDragDuringTracking,
              travelled < Self.clickSlop,
              clickedRow >= 0
        else { return }
        onRowClicked?(clickedRow)
    }
}

// MARK: - NotesOutlineViewWrapper

struct NotesOutlineViewWrapper: NSViewRepresentable {
    static let notePasteboardType = NSPasteboard.PasteboardType("GabeMempin.Buoy.note-row")
    /// Carries the dragged row's node key so a drop can tell a folder child
    /// (which can be unfiled) from the same note's All Notes row (which cannot).
    static let noteSourcePasteboardType = NSPasteboard.PasteboardType("GabeMempin.Buoy.note-row-source")
    static let folderPasteboardType = NSPasteboard.PasteboardType("GabeMempin.Buoy.folder-row")

    static let rowCoordinateSpace = "buoyAllNotesRow"

    var notes: [Note]
    var folders: [Folder]
    /// Flat match list used while searching; sections and drag are off then.
    var searchMatches: [Note]?
    var currentNoteID: String?
    var renamingFolderID: String?
    var actions: AllNotesActions

    var isSearching: Bool { searchMatches != nil }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let outlineView = NotesOutlineView()
        outlineView.headerView = nil
        outlineView.backgroundColor = .clear
        outlineView.rowSizeStyle = .custom
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        outlineView.gridStyleMask = []
        outlineView.style = .plain
        // Selection is drawn by the SwiftUI row from `currentNoteID`.
        outlineView.selectionHighlightStyle = .none
        // The panel is non-activating and the editor keeps first responder;
        // the list must not pull focus away from it on a click.
        outlineView.refusesFirstResponder = true
        // Our own chevron is drawn inside the folder row, so the list needs
        // neither AppKit's disclosure cell nor its indentation.
        outlineView.indentationPerLevel = 0
        outlineView.draggingDestinationFeedbackStyle = .gap
        outlineView.registerForDraggedTypes([
            Self.notePasteboardType,
            Self.folderPasteboardType
        ])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("NoteColumn"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.onRowClicked = { [weak coordinator = context.coordinator] row in
            coordinator?.handleRowClick(row)
        }

        scrollView.documentView = outlineView
        context.coordinator.outlineView = outlineView
        context.coordinator.adopt(self)
        context.coordinator.rebuildTree()
        outlineView.reloadData()
        context.coordinator.applyExpansionState()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let previousSignature = coordinator.tree.signature
        let previousRenders = coordinator.renderSignatures

        coordinator.adopt(self)
        coordinator.rebuildTree()

        guard let outlineView = coordinator.outlineView else { return }

        if coordinator.tree.signature != previousSignature {
            // Structure changed in a way no drop handler already animated
            // (a new note, a delete, a pin toggle, a search edit).
            outlineView.reloadData()
            coordinator.applyExpansionState()
            coordinator.refreshRenderSignatures()
        } else {
            // Same rows — repaint only the ones whose content actually moved.
            coordinator.refreshChangedRows(previous: previousRenders)
        }

        coordinator.scrollToRenamingFolderIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        private var parent: NotesOutlineViewWrapper
        weak var outlineView: NotesOutlineView?

        private var notes: [Note] = []
        private var folders: [Folder] = []
        private var searchMatches: [Note]?
        private var currentNoteID: String?
        private var renamingFolderID: String?
        private var actions: AllNotesActions

        private(set) var tree = AllNotesTree()
        private(set) var renderSignatures: [String: String] = [:]
        private var nodeCache: [String: AllNotesNode] = [:]
        private var hoveredKey: String?
        private var lastRenamingFolderID: String?
        private var dimmedRowKeys: [String] = []
        private var isRestoringExpansion = false

        private static let dragShadowPadding: CGFloat = 8

        init(_ parent: NotesOutlineViewWrapper) {
            self.parent = parent
            self.actions = parent.actions
            super.init()
        }

        func adopt(_ parent: NotesOutlineViewWrapper) {
            self.parent = parent
            self.notes = parent.notes
            self.folders = parent.folders
            self.searchMatches = parent.searchMatches
            self.currentNoteID = parent.currentNoteID
            self.renamingFolderID = parent.renamingFolderID
            self.actions = parent.actions
        }

        private var isSearching: Bool { searchMatches != nil }

        // MARK: Tree

        private func node(
            key: String,
            kind: AllNotesNode.Kind,
            placement: AllNotesNode.Placement
        ) -> AllNotesNode {
            if let cached = nodeCache[key] { return cached }
            let created = AllNotesNode(key: key, kind: kind, placement: placement)
            nodeCache[key] = created
            return created
        }

        private var pinnedNotes: [Note] {
            notes.filter(\.isPinned).sorted { lhs, rhs in
                let lhsOrder = lhs.pinnedOrder ?? Int64.max
                let rhsOrder = rhs.pinnedOrder ?? Int64.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id < rhs.id
            }
        }

        private func notesInFolder(_ folderID: String) -> [Note] {
            notes
                .filter { $0.folderID == folderID }
                .sorted { lhs, rhs in
                    let lhsOrder = lhs.folderOrder ?? Int64.max
                    let rhsOrder = rhs.folderOrder ?? Int64.max
                    if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                    return lhs.id < rhs.id
                }
        }

        func rebuildTree() {
            var built = AllNotesTree()

            if let matches = searchMatches {
                built.topLevel = matches.map {
                    node(
                        key: AllNotesNode.allNotesKey($0.id),
                        kind: .note(id: $0.id),
                        placement: .allNotes
                    )
                }
                built.allNotesRange = 0..<built.topLevel.count
            } else {
                let pinned = pinnedNotes
                for note in pinned {
                    built.topLevel.append(
                        node(
                            key: AllNotesNode.pinnedKey(note.id),
                            kind: .note(id: note.id),
                            placement: .pinned
                        )
                    )
                }
                built.pinnedRange = 0..<pinned.count

                if !folders.isEmpty {
                    if !pinned.isEmpty {
                        built.topLevel.append(
                            node(key: "sep:folders", kind: .divider, placement: .separator)
                        )
                    }
                    let start = built.topLevel.count
                    for folder in folders {
                        let folderNode = node(
                            key: AllNotesNode.folderKey(folder.id),
                            kind: .folder(id: folder.id),
                            placement: .folderRow
                        )
                        folderNode.children = notesInFolder(folder.id).map { child in
                            node(
                                key: AllNotesNode.childKey(folderID: folder.id, noteID: child.id),
                                kind: .note(id: child.id),
                                placement: .folderChild(folderID: folder.id)
                            )
                        }
                        built.topLevel.append(folderNode)
                    }
                    built.folderRange = start..<built.topLevel.count
                }

                if !built.topLevel.isEmpty {
                    built.topLevel.append(
                        node(key: "sep:all", kind: .divider, placement: .separator)
                    )
                }
                let allStart = built.topLevel.count
                for note in notes {
                    built.topLevel.append(
                        node(
                            key: AllNotesNode.allNotesKey(note.id),
                            kind: .note(id: note.id),
                            placement: .allNotes
                        )
                    )
                }
                built.allNotesRange = allStart..<built.topLevel.count
            }

            built.signature = Self.signature(of: built.topLevel)
            tree = built
            pruneNodeCache()
        }

        private static func signature(of topLevel: [AllNotesNode]) -> [String] {
            var flat: [String] = []
            for node in topLevel {
                flat.append(node.key)
                for child in node.children { flat.append("  \(child.key)") }
            }
            return flat
        }

        private func pruneNodeCache() {
            var live = Set<String>()
            for node in tree.topLevel {
                live.insert(node.key)
                for child in node.children { live.insert(child.key) }
            }
            nodeCache = nodeCache.filter { live.contains($0.key) }
            renderSignatures = renderSignatures.filter { live.contains($0.key) }
        }

        private func allNodes() -> [AllNotesNode] {
            tree.topLevel.flatMap { [$0] + $0.children }
        }

        private func note(for id: String) -> Note? {
            notes.first { $0.id == id }
        }

        private func folder(for id: String) -> Folder? {
            folders.first { $0.id == id }
        }

        private func folderNode(for id: String) -> AllNotesNode? {
            tree.topLevel.first { $0.folderID == id }
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? AllNotesNode else { return tree.topLevel.count }
            return node.children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let node = item as? AllNotesNode else { return tree.topLevel[index] }
            return node.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? AllNotesNode)?.folderID != nil
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            guard let node = item as? AllNotesNode else {
                return PanelLayoutMetrics.allNotesNoteRowHeight
            }
            switch node.kind {
            case .note: return PanelLayoutMetrics.allNotesNoteRowHeight
            case .folder: return PanelLayoutMetrics.allNotesFolderRowHeight
            case .divider: return PanelLayoutMetrics.allNotesDividerRowHeight
            }
        }

        /// The folder row draws its own chevron, and with `indentationPerLevel`
        /// at 0 AppKit's disclosure triangle would be drawn at the row's left
        /// edge, on top of it. Expansion is driven by the row click instead.
        func outlineView(
            _ outlineView: NSOutlineView,
            shouldShowOutlineCellForItem item: Any
        ) -> Bool {
            false
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            guard let node = item as? AllNotesNode else { return false }
            return !node.isDivider
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            let rowView = NotesRowView()
            guard let node = item as? AllNotesNode, !node.isDivider else { return rowView }
            rowView.onHoverChange = { [weak self] hovering in
                self?.setHovered(node.key, hovering)
            }
            return rowView
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            viewFor tableColumn: NSTableColumn?,
            item: Any
        ) -> NSView? {
            guard let node = item as? AllNotesNode else { return nil }
            let identifier = NSUserInterfaceItemIdentifier(Self.reuseIdentifier(for: node))
            let hosting: PassthroughHostingView<AnyView>
            if let reused = outlineView.makeView(withIdentifier: identifier, owner: self)
                as? PassthroughHostingView<AnyView> {
                hosting = reused
            } else {
                hosting = PassthroughHostingView<AnyView>(rootView: AnyView(EmptyView()))
                hosting.identifier = identifier
            }
            // Stale regions from the row this view last rendered would misroute
            // the first click after reuse.
            hosting.interactiveRegions = []
            hosting.rootView = content(for: node, hosting: hosting)
            renderSignatures[node.key] = renderSignature(for: node)
            return hosting
        }

        private static func reuseIdentifier(for node: AllNotesNode) -> String {
            switch node.kind {
            case .note: return "AllNotesNoteCell"
            case .folder: return "AllNotesFolderCell"
            case .divider: return "AllNotesDividerCell"
            }
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !isRestoringExpansion,
                  let node = notification.userInfo?["NSObject"] as? AllNotesNode,
                  let folderID = node.folderID
            else { return }
            actions.setFolderExpanded(folderID, true)
            refreshRow(node)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !isRestoringExpansion,
                  let node = notification.userInfo?["NSObject"] as? AllNotesNode,
                  let folderID = node.folderID
            else { return }
            actions.setFolderExpanded(folderID, false)
            refreshRow(node)
        }

        func applyExpansionState() {
            guard let outlineView else { return }
            isRestoringExpansion = true
            for node in tree.topLevel {
                guard let folderID = node.folderID else { continue }
                if folder(for: folderID)?.isExpanded == true {
                    outlineView.expandItem(node)
                } else {
                    outlineView.collapseItem(node)
                }
            }
            isRestoringExpansion = false
        }

        // MARK: Row content

        private func content(
            for node: AllNotesNode,
            hosting: PassthroughHostingView<AnyView>
        ) -> AnyView {
            let space = NotesOutlineViewWrapper.rowCoordinateSpace
            let publishRegions: ([CGRect]) -> Void = { [weak hosting] rects in
                hosting?.interactiveRegions = rects
            }

            switch node.kind {
            case .divider:
                return AnyView(AllNotesSectionDivider())

            case .note(let noteID):
                guard let note = note(for: noteID) else { return AnyView(EmptyView()) }
                return AnyView(
                    NoteRow(
                        note: note,
                        isActive: note.id == currentNoteID,
                        isHovering: hoveredKey == node.key,
                        isIndented: node.parentFolderID != nil,
                        onSelect: { [weak self] in self?.actions.selectNote(note) },
                        onTogglePin: { [weak self] in self?.actions.togglePin(note) },
                        onDelete: { [weak self] in self?.actions.deleteNote(note) }
                    )
                    .coordinateSpace(name: space)
                    .onPreferenceChange(InteractiveRegionKey.self, perform: publishRegions)
                )

            case .folder(let folderID):
                guard let folder = folder(for: folderID) else { return AnyView(EmptyView()) }
                let isExpanded = outlineView?.isItemExpanded(node) ?? false
                return AnyView(
                    FolderRow(
                        folder: folder,
                        noteCount: node.children.count,
                        isExpanded: isExpanded,
                        isHovering: hoveredKey == node.key,
                        isRenaming: renamingFolderID == folder.id,
                        onToggleExpanded: { [weak self] in self?.toggleExpansion(node) },
                        onBeginRename: { [weak self] in self?.actions.setRenamingFolder(folder.id) },
                        onCommitRename: { [weak self] name in
                            self?.actions.renameFolder(folder.id, name)
                            self?.actions.setRenamingFolder(nil)
                        },
                        onCancelRename: { [weak self] in
                            self?.actions.cancelRenameFolder(folder.id)
                        },
                        onDelete: { [weak self] in self?.actions.requestDeleteFolder(folder) }
                    )
                    .coordinateSpace(name: space)
                    .onPreferenceChange(InteractiveRegionKey.self, perform: publishRegions)
                )
            }
        }

        /// Everything about a node that changes how its row draws. Compared on
        /// each update so only genuinely changed rows repaint.
        private func renderSignature(for node: AllNotesNode) -> String {
            switch node.kind {
            case .divider:
                return "divider"
            case .note(let noteID):
                guard let note = note(for: noteID) else { return "missing" }
                return [
                    note.title,
                    note.isPinned ? "1" : "0",
                    note.id == currentNoteID ? "1" : "0",
                    hoveredKey == node.key ? "1" : "0",
                    node.parentFolderID ?? "-"
                ].joined(separator: "|")
            case .folder(let folderID):
                guard let folder = folder(for: folderID) else { return "missing" }
                return [
                    folder.name,
                    String(node.children.count),
                    (outlineView?.isItemExpanded(node) ?? false) ? "1" : "0",
                    hoveredKey == node.key ? "1" : "0",
                    renamingFolderID == folderID ? "1" : "0"
                ].joined(separator: "|")
            }
        }

        func refreshRenderSignatures() {
            for node in allNodes() {
                renderSignatures[node.key] = renderSignature(for: node)
            }
        }

        func refreshChangedRows(previous: [String: String]) {
            for node in allNodes() {
                let current = renderSignature(for: node)
                guard previous[node.key] != current else {
                    renderSignatures[node.key] = current
                    continue
                }
                refreshRow(node)
            }
        }

        /// Repaints one row in place by swapping its SwiftUI root view. Cheaper
        /// than `reloadItem`, which tears the cell view down and rebuilds it.
        private func refreshRow(_ node: AllNotesNode) {
            renderSignatures[node.key] = renderSignature(for: node)
            guard let outlineView else { return }
            let row = outlineView.row(forItem: node)
            guard row >= 0,
                  let hosting = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
                    as? PassthroughHostingView<AnyView>
            else { return }
            hosting.rootView = content(for: node, hosting: hosting)
        }

        /// A folder created with several pinned notes above it can land below
        /// the list's 300pt fold, which would put the rename field — already
        /// first responder — out of sight.
        func scrollToRenamingFolderIfNeeded() {
            guard renamingFolderID != lastRenamingFolderID else { return }
            lastRenamingFolderID = renamingFolderID
            guard let renamingFolderID,
                  let outlineView,
                  let node = folderNode(for: renamingFolderID)
            else { return }
            let row = outlineView.row(forItem: node)
            guard row >= 0 else { return }
            outlineView.scrollRowToVisible(row)
        }

        private func setHovered(_ key: String, _ hovering: Bool) {
            let newKey: String? = hovering ? key : (hoveredKey == key ? nil : hoveredKey)
            guard newKey != hoveredKey else { return }
            let previous = hoveredKey
            hoveredKey = newKey
            if let previous, let node = nodeCache[previous] { refreshRow(node) }
            if let newKey, let node = nodeCache[newKey] { refreshRow(node) }
        }

        // MARK: Clicks

        func handleRowClick(_ row: Int) {
            guard let outlineView,
                  let node = outlineView.item(atRow: row) as? AllNotesNode
            else { return }

            switch node.kind {
            case .divider:
                return
            case .note(let noteID):
                guard let note = note(for: noteID) else { return }
                actions.selectNote(note)
            case .folder(let folderID):
                // A folder row toggles itself; the chevron is an affordance,
                // not a separate target.
                guard renamingFolderID != folderID else { return }
                toggleExpansion(node)
            }
        }

        func toggleExpansion(_ node: AllNotesNode) {
            guard let outlineView else { return }
            let duration = BuoyMotion.duration(0.2)
            let target: NSOutlineView = duration > 0 ? outlineView.animator() : outlineView
            if outlineView.isItemExpanded(node) {
                target.collapseItem(node)
            } else {
                target.expandItem(node)
            }
        }

        // MARK: Drag source

        func outlineView(
            _ outlineView: NSOutlineView,
            pasteboardWriterForItem item: Any
        ) -> NSPasteboardWriting? {
            guard !isSearching, let node = item as? AllNotesNode else { return nil }
            // Called synchronously the moment AppKit decides this press is a
            // drag — earlier and more reliably than the session's `willBeginAt`
            // — so it is the signal that stops `mouseDown` reporting a click.
            (outlineView as? NotesOutlineView)?.didStartDragDuringTracking = true
            switch node.kind {
            case .divider:
                return nil
            case .folder(let folderID):
                guard renamingFolderID != folderID else { return nil }
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(
                    folderID,
                    forType: NotesOutlineViewWrapper.folderPasteboardType
                )
                return pasteboardItem
            case .note(let noteID):
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(
                    noteID,
                    forType: NotesOutlineViewWrapper.notePasteboardType
                )
                pasteboardItem.setString(
                    node.key,
                    forType: NotesOutlineViewWrapper.noteSourcePasteboardType
                )
                return pasteboardItem
            }
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forItems draggedItems: [Any]
        ) {
            (outlineView as? NotesOutlineView)?.didStartDragDuringTracking = true

            let nodes = draggedItems.compactMap { $0 as? AllNotesNode }
            var previews: [(NSRect, NSImage)] = []
            for node in nodes {
                let row = outlineView.row(forItem: node)
                guard row >= 0,
                      let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false)
                else { continue }
                let frame = outlineView
                    .convert(rowView.bounds, from: rowView)
                    .insetBy(dx: -Self.dragShadowPadding, dy: -Self.dragShadowPadding)
                previews.append((frame, Self.cardImage(for: rowView)))
            }

            var index = 0
            session.enumerateDraggingItems(
                options: [],
                for: outlineView,
                classes: [NSPasteboardItem.self],
                searchOptions: [:]
            ) { draggingItem, _, _ in
                guard index < previews.count else { return }
                let (frame, image) = previews[index]
                draggingItem.setDraggingFrame(frame, contents: image)
                index += 1
            }

            // The card is the lift; the row it came from recedes behind it.
            dimmedRowKeys = nodes.map(\.key)
            setSourceRowAlpha(0.28)
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            setSourceRowAlpha(1)
            dimmedRowKeys = []
            // No mouseExited arrives while a session is running, so the source
            // row would otherwise keep its hover buttons after the drop.
            if let hoveredKey, let node = nodeCache[hoveredKey] {
                self.hoveredKey = nil
                refreshRow(node)
            }
        }

        private func setSourceRowAlpha(_ alpha: CGFloat) {
            guard let outlineView else { return }
            let duration = BuoyMotion.duration(alpha < 1 ? 0.08 : 0.12)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                for key in dimmedRowKeys {
                    guard let node = nodeCache[key] else { continue }
                    let row = outlineView.row(forItem: node)
                    guard row >= 0,
                          let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false)
                    else { continue }
                    if duration > 0 {
                        rowView.animator().alphaValue = alpha
                    } else {
                        rowView.alphaValue = alpha
                    }
                }
            }
        }

        private static func cardImage(for rowView: NSTableRowView) -> NSImage {
            let snapshot = NSImage(size: rowView.bounds.size)
            if let representation = rowView.bitmapImageRepForCachingDisplay(in: rowView.bounds) {
                rowView.cacheDisplay(in: rowView.bounds, to: representation)
                snapshot.addRepresentation(representation)
            }

            let padding = dragShadowPadding
            let image = NSImage(
                size: NSSize(
                    width: rowView.bounds.width + padding * 2,
                    height: rowView.bounds.height + padding * 2
                )
            )
            let cardRect = NSRect(
                x: padding,
                y: padding,
                width: rowView.bounds.width,
                height: rowView.bounds.height
            )

            image.lockFocus()
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
            NSBezierPath(roundedRect: cardRect, xRadius: 7, yRadius: 7).fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: cardRect, xRadius: 7, yRadius: 7).addClip()
            snapshot.draw(in: cardRect)
            NSGraphicsContext.restoreGraphicsState()
            image.unlockFocus()
            return image
        }

        // MARK: Drop

        /// What a drop at a given position would do. Resolved once and reused
        /// by both `validateDrop` and `acceptDrop` so the highlight can never
        /// promise something the commit does not do.
        private enum DropPlan {
            case reorderPinned(noteID: String, to: Int)
            case reorderFolders(folderID: String, to: Int)
            case fileIntoFolder(noteID: String, folderID: String, index: Int?)
            case reorderInFolder(folderID: String, noteID: String, to: Int)
            case unfile(noteID: String, folderID: String)
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            var targetItem = item as? AllNotesNode
            var targetIndex = index

            // A drop landing *on* a note or a divider is really an insertion
            // above that row. Retarget so the user is not fighting for the
            // 4pt seam between rows.
            if targetIndex == NSOutlineViewDropOnItemIndex,
               let node = targetItem,
               node.folderID == nil {
                if node.isDivider {
                    // A divider's own index sits outside every band, so taking
                    // it literally rejected the drop. It reads as "the start of
                    // the section under this line".
                    targetItem = nil
                    targetIndex = node.key == "sep:all"
                        ? tree.allNotesRange.lowerBound
                        : tree.folderRange.lowerBound
                } else if let parentID = node.parentFolderID,
                          let parent = folderNode(for: parentID),
                          let childIndex = parent.children.firstIndex(of: node) {
                    targetItem = parent
                    targetIndex = childIndex
                } else if let topIndex = tree.topLevel.firstIndex(of: node) {
                    targetItem = nil
                    targetIndex = topIndex
                }
                outlineView.setDropItem(targetItem, dropChildIndex: targetIndex)
            }

            guard resolvePlan(info: info, item: targetItem, index: targetIndex) != nil else {
                return []
            }
            return .move
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard let plan = resolvePlan(info: info, item: item as? AllNotesNode, index: index) else {
                return false
            }
            apply(plan, in: outlineView)
            return true
        }

        private func resolvePlan(
            info: NSDraggingInfo,
            item: AllNotesNode?,
            index: Int
        ) -> DropPlan? {
            guard !isSearching else { return nil }
            let pasteboard = info.draggingPasteboard

            // Folder rows reorder among themselves, nothing else.
            if let folderID = pasteboard.string(
                forType: NotesOutlineViewWrapper.folderPasteboardType
            ) {
                guard item == nil,
                      !tree.folderRange.isEmpty,
                      index >= tree.folderRange.lowerBound,
                      index <= tree.folderRange.upperBound,
                      let source = folders.firstIndex(where: { $0.id == folderID })
                else { return nil }
                var destination = index - tree.folderRange.lowerBound
                if source < destination { destination -= 1 }
                guard destination != source else { return nil }
                return .reorderFolders(folderID: folderID, to: destination)
            }

            guard let noteID = pasteboard.string(
                    forType: NotesOutlineViewWrapper.notePasteboardType
                  ),
                  let sourceKey = pasteboard.string(
                    forType: NotesOutlineViewWrapper.noteSourcePasteboardType
                  ),
                  let draggedNote = note(for: noteID)
            else { return nil }

            let sourceFolderID = nodeCache[sourceKey]?.parentFolderID
            let sourcePlacement = nodeCache[sourceKey]?.placement

            // Onto or inside a folder.
            if let targetFolderID = item?.folderID {
                let alreadyFiledHere = draggedNote.folderID == targetFolderID

                if index == NSOutlineViewDropOnItemIndex {
                    guard !alreadyFiledHere else { return nil }
                    return .fileIntoFolder(noteID: noteID, folderID: targetFolderID, index: nil)
                }

                if alreadyFiledHere {
                    // Only a row dragged *from* this folder reorders it; the
                    // same note's All Notes row would be a no-op move.
                    guard sourceFolderID == targetFolderID else { return nil }
                    let ordered = notesInFolder(targetFolderID).map(\.id)
                    guard let source = ordered.firstIndex(of: noteID) else { return nil }
                    var destination = index
                    if source < destination { destination -= 1 }
                    guard destination != source else { return nil }
                    return .reorderInFolder(
                        folderID: targetFolderID,
                        noteID: noteID,
                        to: destination
                    )
                }

                return .fileIntoFolder(noteID: noteID, folderID: targetFolderID, index: index)
            }

            guard item == nil, index >= 0 else { return nil }

            // Pinned band: reorder, and only for a row dragged from that band.
            if sourcePlacement == .pinned,
               draggedNote.isPinned,
               index >= tree.pinnedRange.lowerBound,
               index <= tree.pinnedRange.upperBound {
                let ordered = pinnedNotes.map(\.id)
                guard let source = ordered.firstIndex(of: noteID) else { return nil }
                var destination = index - tree.pinnedRange.lowerBound
                if source < destination { destination -= 1 }
                guard destination != source else { return nil }
                return .reorderPinned(noteID: noteID, to: destination)
            }

            // All Notes band: the only thing a drop here means is "take this
            // out of its folder". All Notes itself is chronological.
            if let sourceFolderID,
               index >= tree.allNotesRange.lowerBound,
               index <= tree.allNotesRange.upperBound {
                return .unfile(noteID: noteID, folderID: sourceFolderID)
            }

            return nil
        }

        private func apply(_ plan: DropPlan, in outlineView: NSOutlineView) {
            switch plan {
            case .reorderPinned(let noteID, let destination):
                var ordered = pinnedNotes.map(\.id)
                guard let source = ordered.firstIndex(of: noteID) else { return }
                let moved = ordered.remove(at: source)
                ordered.insert(moved, at: min(destination, ordered.count))

                let from = tree.pinnedRange.lowerBound + source
                let to = tree.pinnedRange.lowerBound + min(destination, ordered.count - 1)
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = BuoyMotion.duration(0.22)
                outlineView.beginUpdates()
                let node = tree.topLevel.remove(at: from)
                tree.topLevel.insert(node, at: to)
                outlineView.moveItem(at: from, inParent: nil, to: to, inParent: nil)
                outlineView.endUpdates()
                NSAnimationContext.endGrouping()
                tree.signature = Self.signature(of: tree.topLevel)
                actions.reorderPinned(ordered)

            case .reorderFolders(let folderID, let destination):
                var ordered = folders.map(\.id)
                guard let source = ordered.firstIndex(of: folderID) else { return }
                let moved = ordered.remove(at: source)
                ordered.insert(moved, at: min(destination, ordered.count))

                let from = tree.folderRange.lowerBound + source
                let to = tree.folderRange.lowerBound + min(destination, ordered.count - 1)
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = BuoyMotion.duration(0.22)
                outlineView.beginUpdates()
                let node = tree.topLevel.remove(at: from)
                tree.topLevel.insert(node, at: to)
                outlineView.moveItem(at: from, inParent: nil, to: to, inParent: nil)
                outlineView.endUpdates()
                NSAnimationContext.endGrouping()
                tree.signature = Self.signature(of: tree.topLevel)
                actions.reorderFolders(ordered)

            case .reorderInFolder(let folderID, let noteID, let destination):
                guard let parent = folderNode(for: folderID) else { return }
                var ordered = notesInFolder(folderID).map(\.id)
                guard let source = ordered.firstIndex(of: noteID) else { return }
                let moved = ordered.remove(at: source)
                let clamped = min(destination, ordered.count)
                ordered.insert(moved, at: clamped)

                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = BuoyMotion.duration(0.22)
                outlineView.beginUpdates()
                let node = parent.children.remove(at: source)
                parent.children.insert(node, at: clamped)
                outlineView.moveItem(at: source, inParent: parent, to: clamped, inParent: parent)
                outlineView.endUpdates()
                NSAnimationContext.endGrouping()
                tree.signature = Self.signature(of: tree.topLevel)
                actions.reorderInFolder(folderID, ordered)

            case .fileIntoFolder(let noteID, let folderID, let index):
                guard let parent = folderNode(for: folderID) else { return }
                let previousFolderID = note(for: noteID)?.folderID
                let insertIndex = min(max(index ?? parent.children.count, 0), parent.children.count)
                let child = node(
                    key: AllNotesNode.childKey(folderID: folderID, noteID: noteID),
                    kind: .note(id: noteID),
                    placement: .folderChild(folderID: folderID)
                )

                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = BuoyMotion.duration(0.22)
                outlineView.beginUpdates()
                if let previousFolderID,
                   previousFolderID != folderID,
                   let previousParent = folderNode(for: previousFolderID),
                   let removalIndex = previousParent.children.firstIndex(where: {
                       $0.noteID == noteID
                   }) {
                    previousParent.children.remove(at: removalIndex)
                    outlineView.removeItems(
                        at: IndexSet(integer: removalIndex),
                        inParent: previousParent,
                        withAnimation: .effectFade
                    )
                }
                parent.children.insert(child, at: insertIndex)
                outlineView.insertItems(
                    at: IndexSet(integer: insertIndex),
                    inParent: parent,
                    withAnimation: .effectGap
                )
                outlineView.endUpdates()
                NSAnimationContext.endGrouping()
                tree.signature = Self.signature(of: tree.topLevel)
                actions.fileNote(noteID, folderID, insertIndex)
                // The row's count label changed.
                refreshRow(parent)

            case .unfile(let noteID, let folderID):
                guard let parent = folderNode(for: folderID),
                      let removalIndex = parent.children.firstIndex(where: { $0.noteID == noteID })
                else { return }
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = BuoyMotion.duration(0.22)
                outlineView.beginUpdates()
                parent.children.remove(at: removalIndex)
                outlineView.removeItems(
                    at: IndexSet(integer: removalIndex),
                    inParent: parent,
                    withAnimation: .effectFade
                )
                outlineView.endUpdates()
                NSAnimationContext.endGrouping()
                tree.signature = Self.signature(of: tree.topLevel)
                actions.unfileNote(noteID)
                refreshRow(parent)
            }
        }
    }
}
