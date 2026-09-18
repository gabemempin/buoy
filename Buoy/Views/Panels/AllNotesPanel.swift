import AppKit
import SwiftUI

struct AllNotesPanel: View {
    @Binding var isShowing: Bool
    var notes: [Note]
    var folders: [Folder]
    var currentNoteID: String?
    var renamingFolderID: String?
    var onCreateFolder: () -> Void
    var actions: AllNotesActions

    @State private var searchText = ""

    /// Flat match list while searching. `nil` means "not searching", which is
    /// what turns the sections and every drag back on.
    private var searchMatches: [Note]? {
        guard !searchText.isEmpty else { return nil }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || NotePlainText.of($0).localizedCaseInsensitiveContains(searchText)
        }
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private var isEmpty: Bool {
        if let searchMatches { return searchMatches.isEmpty }
        return notes.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            SearchFieldWrapper(text: $searchText, placeholder: "Search notes...")
                .frame(height: 22)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            Divider()

            if isEmpty {
                Text("No matching notes")
                    .font(BuoyFont.control)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                    .frame(maxHeight: PanelLayoutMetrics.allNotesListMaxHeight, alignment: .top)
            } else {
                NotesOutlineViewWrapper(
                    notes: notes,
                    folders: folders,
                    searchMatches: searchMatches,
                    currentNoteID: currentNoteID,
                    renamingFolderID: renamingFolderID,
                    actions: listActions
                )
                .frame(maxHeight: PanelLayoutMetrics.allNotesListMaxHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .background(WindowDragBlocker())
        .buoyGlassPanel(cornerRadius: 14)
        .shadow(radius: 8)
        .transition(
            BuoyMotion.transition(
                .scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity)
            )
        )
        .onChange(of: isShowing) { _, showing in
            if !showing {
                searchText = ""
                actions.setRenamingFolder(nil)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("All Notes")
                .font(BuoyFont.sectionTitle)

            Spacer()

            // Disabled while searching: the list is flattened then, so a new
            // folder's row would not be built and its rename would sit armed
            // until the search was cleared.
            Button(action: onCreateFolder) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.buoyControlFill))
            }
            .buttonStyle(.plain)
            .disabled(isSearching)
            .opacity(isSearching ? 0.4 : 1)
            .help("New folder")
            .accessibilityLabel("New folder")
            .pointingHandCursor()

            Button {
                withAnimation(BuoyMotion.easeOut(0.16)) { isShowing = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.buoyControlFill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close All Notes")
            .pointingHandCursor()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// Selecting a note also closes the panel; everything else is passed
    /// straight through.
    private var listActions: AllNotesActions {
        var resolved = actions
        let close = { withAnimation(BuoyMotion.easeOut(0.16)) { isShowing = false } }
        let select = actions.selectNote
        resolved.selectNote = { note in
            select(note)
            close()
        }
        return resolved
    }
}

// MARK: - Section header

/// Names a section of the list: Pinned, Folders, All Notes.
///
/// This replaced a bare hairline. The rule alone said the list was grouped but
/// never why, so the pinned band and a folder's contents read as an unexplained
/// split rather than as sections.
struct AllNotesSectionHeader: View {
    let title: String
    /// The first header in the list has nothing above it to divide from.
    let showsRule: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsRule {
                Rectangle()
                    .fill(Color.buoyOverlayStroke)
                    .frame(height: 1)
                    .padding(.bottom, 6)
            }
            Text(title.uppercased())
                .font(BuoyFont.caption.weight(.semibold))
                .kerning(0.5)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.top, showsRule ? 4 : 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) section")
    }
}

// MARK: - NoteRow

struct NoteRow: View {
    let note: Note
    let isActive: Bool
    /// Driven by the row's AppKit tracking area, not SwiftUI's `onHover`: the
    /// row content is not hit-testable, so AppKit is the layer that knows.
    let isHovering: Bool
    /// True for a note shown inside a folder.
    let isIndented: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    private var space: String { NotesOutlineViewWrapper.rowCoordinateSpace }

    var body: some View {
        HStack(spacing: 4) {
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(isActive ? BuoyFont.sectionTitle : BuoyFont.control)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering || note.isPinned {
                Button(action: onTogglePin) {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 9))
                        .foregroundStyle(note.isPinned ? Color.accentColor : Color.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.buoyControlFill))
                }
                .buttonStyle(.plain)
                .help(note.isPinned ? "Unpin note" : "Pin note")
                .accessibilityLabel(note.isPinned ? "Unpin note" : "Pin note")
                .pointingHandCursor()
                .interactiveRegion(in: space)
                .transition(.opacity)
            }

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.buoyControlFill))
                }
                .buttonStyle(.plain)
                .help("Delete note")
                .accessibilityLabel("Delete note")
                .pointingHandCursor()
                .interactiveRegion(in: space)
                .transition(.opacity)
            }
        }
        .padding(.leading, isIndented ? 10 + PanelLayoutMetrics.allNotesChildIndent : 10)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive ? Color.buoySelectionFill : Color.clear)
                .padding(.leading, isIndented ? PanelLayoutMetrics.allNotesChildIndent : 0)
        )
        .animation(BuoyMotion.easeInOut(0.1), value: isHovering)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(note.title.isEmpty ? "Untitled" : note.title)
        .accessibilityValue(note.isPinned ? "Pinned" : "")
        // The row carries no tap gesture — that would swallow the mouseDown the
        // outline view needs to start a drag — so VoiceOver's press action has
        // to be supplied explicitly or the row is unopenable without a mouse.
        .accessibilityAction { onSelect() }
    }
}

// MARK: - FolderRow

struct FolderRow: View {
    let folder: Folder
    let noteCount: Int
    let isExpanded: Bool
    let isHovering: Bool
    let isRenaming: Bool
    let onToggleExpanded: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: (String) -> Void
    let onCancelRename: () -> Void
    let onDelete: () -> Void

    private var space: String { NotesOutlineViewWrapper.rowCoordinateSpace }

    var body: some View {
        HStack(spacing: 5) {
            // Affordance only — the whole row toggles, so this is not a button
            // and never competes with the row's own click handling.
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 10)
                .accessibilityHidden(true)

            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if isRenaming {
                InlineRenameField(
                    text: folder.name,
                    onCommit: onCommitRename,
                    onCancel: onCancelRename
                )
                .frame(height: 16)
                .interactiveRegion(in: space)
            } else {
                Text(folder.displayName)
                    .font(BuoyFont.control)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(noteCount)")
                    .font(BuoyFont.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 4)

            if isHovering && !isRenaming {
                Button(action: onBeginRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.buoyControlFill))
                }
                .buttonStyle(.plain)
                .help("Rename folder")
                .accessibilityLabel("Rename folder")
                .pointingHandCursor()
                .interactiveRegion(in: space)
                .transition(.opacity)

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.buoyControlFill))
                }
                .buttonStyle(.plain)
                .help("Delete folder")
                .accessibilityLabel("Delete folder")
                .pointingHandCursor()
                .interactiveRegion(in: space)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .animation(BuoyMotion.easeInOut(0.1), value: isHovering)
        .animation(BuoyMotion.easeOut(0.18), value: isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Folder \(folder.displayName)")
        .accessibilityValue(
            "\(noteCount) \(noteCount == 1 ? "note" : "notes"), "
                + (isExpanded ? "expanded" : "collapsed")
        )
        .accessibilityAction { onToggleExpanded() }
    }
}

// MARK: - InlineRenameField

/// Borderless single-line field for renaming a folder in place.
///
/// AppKit rather than SwiftUI's `TextField` for the same reason the search and
/// title fields are: the panel is non-activating, so focus has to be taken
/// explicitly through the window.
struct InlineRenameField: NSViewRepresentable {
    var text: String
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        // No focus ring, matching every other borderless field in the app.
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 12)
        field.textColor = .labelColor
        field.delegate = context.coordinator
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.lineBreakMode = .byTruncatingTail
        field.setAccessibilityLabel("Folder name")

        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Only the closures are refreshed. The field's text is seeded once in
        // `makeNSView` and never pushed again: the row re-renders on hover and
        // on every store change while the rename is open, and writing `text`
        // back here would overwrite whatever the user has typed so far with the
        // folder's *stored* name.
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineRenameField
        /// Return commits and then AppKit ends editing, which would otherwise
        /// commit a second time.
        var hasFinished = false

        init(_ parent: InlineRenameField) {
            self.parent = parent
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                finish(committing: control.stringValue)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finish(committing: nil)
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            finish(committing: field.stringValue)
        }

        private func finish(committing value: String?) {
            guard !hasFinished else { return }
            hasFinished = true
            if let value {
                parent.onCommit(value)
            } else {
                parent.onCancel()
            }
        }
    }
}
