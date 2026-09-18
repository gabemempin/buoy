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
        // Without this the list runs straight into the panel's rounded corner,
        // so the scroller's track crossed the curve instead of following it.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                // Matches SettingsPanel's title exactly; the two panels sit in
                // the same corner and a size mismatch between them shows.
                .font(.system(size: 14, weight: .semibold))

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
                // Same contrast as the panel's own "All Notes" title, in both
                // appearances. At `.tertiary` these were barely legible.
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.top, showsRule ? 4 : 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) section")
    }
}

// MARK: - Row action button

/// A symbol-only button for a list row: pin, delete, rename.
///
/// The resting state is a bare glyph — Apple's own lists (Finder, Mail) do not
/// sit a filled chip behind every row action, and at this row height the chips
/// read as heavier than the row itself. The fill is the *press* state instead,
/// which the HIG asks for outright: "Always include a press state for a custom
/// button. Without a press state, a button can feel unresponsive." The hit
/// region is deliberately larger than the glyph for the same reason the HIG
/// gives for generous hit targets.
struct RowActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 22, height: 22)
            .background(
                Circle()
                    .fill(Color.buoyControlFill)
                    .opacity(configuration.isPressed ? 1 : 0)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .contentShape(Circle())
            .animation(BuoyMotion.easeOut(0.1), value: configuration.isPressed)
    }
}

struct RowActionButton: View {
    let systemName: String
    let label: String
    var tint: Color = .secondary
    let action: () -> Void

    private var space: String { NotesOutlineViewWrapper.rowCoordinateSpace }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tint)
        }
        .buttonStyle(RowActionButtonStyle())
        .help(label)
        .accessibilityLabel(label)
        .pointingHandCursor()
        .interactiveRegion(in: space)
        .transition(.opacity)
    }
}

// MARK: - Row folder menu

/// The "move to folder" control in a note row.
///
/// A real `Menu` — so it opens a system popup at the button rather than a
/// second Buoy panel floating over the first one. It styles its own label
/// because a `ButtonStyle` does not apply to a `Menu`.
struct RowFolderMenu: View {
    let currentFolderID: String?
    let folders: [Folder]
    let onMoveToFolder: (String) -> Void
    let onMoveToNewFolder: () -> Void
    let onRemoveFromFolder: () -> Void

    private var space: String { NotesOutlineViewWrapper.rowCoordinateSpace }

    /// Empty string stands for "no folder", so the picker always has a tag it
    /// can match even when the note is unfiled.
    private var folderSelection: Binding<String> {
        Binding(
            get: { currentFolderID ?? "" },
            set: { selected in
                guard !selected.isEmpty, selected != currentFolderID else { return }
                onMoveToFolder(selected)
            }
        )
    }

    var body: some View {
        Menu {
            if !folders.isEmpty {
                // An inline `Picker` rather than a list of buttons: it is what
                // draws the native checkmark against the folder the note is
                // already in. A `Label(_:systemImage: "checkmark")` does not
                // render one in a macOS menu.
                Picker("Folder", selection: folderSelection) {
                    ForEach(folders) { folder in
                        Text(folder.displayName).tag(folder.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Divider()
            }

            Button("New Folder…") { onMoveToNewFolder() }

            if currentFolderID != nil {
                Divider()
                Button("Remove from Folder") { onRemoveFromFolder() }
            }
        } label: {
            Image(systemName: currentFolderID == nil ? "folder" : "folder.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22, height: 22)
        .contentShape(Circle())
        .help("Move to folder")
        .accessibilityLabel("Move to folder")
        .pointingHandCursor()
        .interactiveRegion(in: space)
        .transition(.opacity)
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
    let folders: [Folder]
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onMoveToFolder: (String) -> Void
    let onMoveToNewFolder: () -> Void
    let onRemoveFromFolder: () -> Void
    let onDelete: () -> Void

    private var space: String { NotesOutlineViewWrapper.rowCoordinateSpace }

    var body: some View {
        HStack(spacing: 2) {
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(isActive ? BuoyFont.sectionTitle : BuoyFont.control)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering || note.isPinned {
                RowActionButton(
                    systemName: note.isPinned ? "pin.fill" : "pin",
                    label: note.isPinned ? "Unpin note" : "Pin note",
                    tint: note.isPinned ? Color.accentColor : Color.secondary,
                    action: onTogglePin
                )
            }

            if isHovering {
                RowFolderMenu(
                    currentFolderID: note.folderID,
                    folders: folders,
                    onMoveToFolder: onMoveToFolder,
                    onMoveToNewFolder: onMoveToNewFolder,
                    onRemoveFromFolder: onRemoveFromFolder
                )

                RowActionButton(
                    systemName: "xmark",
                    label: "Delete note",
                    action: onDelete
                )
            }
        }
        // Text sits 10pt from the panel edge, level with the section headers.
        // The pill it sits in stops 4pt short of that edge so the fill never
        // runs into the panel's rounded corner.
        .padding(.leading, 6)
        .padding(.trailing, 2)
        // The pill needs to sit *inside* the row with air above and below, or
        // consecutive rows read as one block and the rounding has nothing to
        // round against.
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.buoySelectionFill : Color.clear)
        )
        .padding(.leading, 4 + (isIndented ? PanelLayoutMetrics.allNotesChildIndent : 0))
        .padding(.trailing, 4)
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
                // Baseline-aligned: the count is a smaller type size, so
                // centering it against the name's frame floats it high.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(folder.displayName)
                        .font(BuoyFont.control)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(noteCount)")
                        .font(BuoyFont.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }

            Spacer(minLength: 4)

            if isHovering && !isRenaming {
                RowActionButton(
                    systemName: "pencil",
                    label: "Rename folder",
                    action: onBeginRename
                )
                RowActionButton(
                    systemName: "xmark",
                    label: "Delete folder",
                    action: onDelete
                )
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .padding(.vertical, 5)
        .padding(.leading, 4)
        .padding(.trailing, 4)
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

    /// Clears the field editor's background at the one moment it is reliably
    /// available and already configured: right after `super.becomeFirstResponder`
    /// installs it.
    ///
    /// The window's field editor is shared and AppKit re-configures it from the
    /// cell every time editing starts, so anything set on the `NSTextField`
    /// beforehand — or from `controlTextDidBeginEditing`, which fires around
    /// the same pass — does not survive. Left alone it draws an opaque
    /// background, which is the gray box that appeared behind a folder name in
    /// Dark Mode.
    final class TransparentTextField: NSTextField {
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted, let editor = currentEditor() as? NSTextView {
                editor.drawsBackground = false
                editor.backgroundColor = .clear
            }
            return accepted
        }
    }

    func makeNSView(context: Context) -> TransparentTextField {
        let field = TransparentTextField(string: text)
        field.isBordered = false
        // `NSTextField(string:)` is the *bezeled* convenience init, and
        // `isBordered` is a separate cell flag from `isBezeled` — clearing one
        // leaves the other. The leftover square bezel is what drew a gray box
        // behind the text while editing in Dark Mode.
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
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

    func updateNSView(_ nsView: TransparentTextField, context: Context) {
        // Re-assert it on every pass too: the row re-renders while the rename
        // is open, and the shared editor can be reconfigured underneath us.
        if let editor = nsView.currentEditor() as? NSTextView {
            editor.drawsBackground = false
            editor.backgroundColor = .clear
        }
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

        /// The window's shared field editor is configured by AppKit when
        /// editing begins, *after* everything set on the field itself, and it
        /// arrives drawing an opaque background — the gray box that showed up
        /// behind the name in Dark Mode. Clearing the field's own
        /// `drawsBackground` does not reach it; it has to be turned off here,
        /// once the editor actually exists.
        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField,
                  let editor = field.currentEditor() as? NSTextView
            else { return }
            editor.drawsBackground = false
            editor.backgroundColor = .clear
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
