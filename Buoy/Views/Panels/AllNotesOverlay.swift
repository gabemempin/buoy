import SwiftUI

/// Mounts the All Notes panel in the top-trailing corner and wires it to the
/// store.
///
/// Extracted from `ContentView` deliberately: that view's `body` is at the
/// type-checker's time budget, and the panel now takes a dozen closures.
/// Keeping them here costs `ContentView` a single call site.
struct AllNotesOverlay: View {
    @Binding var isShowing: Bool
    var noteStore: NoteStore
    @Binding var renamingFolderID: String?
    var onDeleteNote: (Note) -> Void
    var onDeleteFolder: (Folder) -> Void
    var onFocusEditor: () -> Void

    /// The folder created by the last "New folder" press, while its name is
    /// still untouched. Abandoning that rename removes the folder instead of
    /// leaving a row called "New Folder" behind.
    @State private var freshFolderID: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                if isShowing {
                    AllNotesPanel(
                        isShowing: $isShowing,
                        notes: noteStore.notes,
                        folders: noteStore.folders,
                        currentNoteID: noteStore.currentNote?.id,
                        renamingFolderID: renamingFolderID,
                        onCreateFolder: createFolder,
                        actions: actions
                    )
                    .frame(
                        width: max(
                            CGFloat.zero,
                            proxy.size.width - (PanelLayoutMetrics.overlayHorizontalInset * 2)
                        ),
                        alignment: .top
                    )
                    .frame(
                        maxHeight: max(
                            CGFloat.zero,
                            proxy.size.height
                                - PanelLayoutMetrics.allNotesTopInset
                                - PanelLayoutMetrics.allNotesBottomInset
                        ),
                        alignment: .top
                    )
                    .padding(.top, PanelLayoutMetrics.allNotesTopInset)
                    .padding(.trailing, PanelLayoutMetrics.overlayHorizontalInset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .animation(BuoyMotion.easeOut(0.16), value: isShowing)
        .allowsHitTesting(isShowing)
    }

    private func createFolder() {
        guard let folder = noteStore.createFolder() else { return }
        // Land straight in rename mode: a folder called "New Folder" is never
        // what the user wanted, and naming it is the next thing they will do.
        freshFolderID = folder.id
        renamingFolderID = folder.id
    }

    private func commitRename(_ folderID: String, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, freshFolderID == folderID {
            noteStore.deleteFolder(folderID)
        } else {
            noteStore.renameFolder(folderID, to: name)
        }
        freshFolderID = nil
    }

    private func cancelRename(_ folderID: String) {
        renamingFolderID = nil
        if freshFolderID == folderID {
            noteStore.deleteFolder(folderID)
        }
        freshFolderID = nil
    }

    private var actions: AllNotesActions {
        AllNotesActions(
            selectNote: { note in
                noteStore.switchNote(to: note)
                onFocusEditor()
            },
            deleteNote: onDeleteNote,
            togglePin: { noteStore.togglePin($0) },
            reorderPinned: { noteStore.reorderPinnedNotes($0) },
            reorderFolders: { noteStore.reorderFolders($0) },
            fileNote: { noteID, folderID, index in
                noteStore.fileNote(noteID, inFolder: folderID, at: index)
            },
            unfileNote: { noteStore.unfileNote($0) },
            reorderInFolder: { folderID, orderedIDs in
                noteStore.reorderNotes(inFolder: folderID, orderedIDs: orderedIDs)
            },
            renameFolder: commitRename,
            cancelRenameFolder: cancelRename,
            requestDeleteFolder: onDeleteFolder,
            setFolderExpanded: { folderID, expanded in
                noteStore.setFolderExpanded(folderID, expanded)
            },
            setRenamingFolder: { renamingFolderID = $0 }
        )
    }
}
