import SwiftUI

struct AllNotesPanel: View {
    @Binding var isShowing: Bool
    var notes: [Note]
    var currentNoteID: String?
    var onSelect: (Note) -> Void
    var onDelete: (Note) -> Void
    var onTogglePin: (Note) -> Void
    var onReorderPinned: ([String]) -> Void

    @State private var searchText = ""

    private var filteredNotes: [Note] {
        let matches: [Note]
        if searchText.isEmpty {
            matches = notes
        } else {
            matches = notes.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || NotePlainText.of($0).localizedCaseInsensitiveContains(searchText)
            }
        }
        let pinned = matches.filter(\.isPinned).sorted { lhs, rhs in
            let lhsOrder = lhs.pinnedOrder ?? Int64.max
            let rhsOrder = rhs.pinnedOrder ?? Int64.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id < rhs.id
        }
        return pinned + matches.filter { !$0.isPinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("All Notes")
                    .font(BuoyFont.sectionTitle)
                Spacer()
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

            Divider()

            //Search bar
            SearchFieldWrapper(text: $searchText, placeholder: "Search notes...")
                .frame(height: 22)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            Divider()

            if filteredNotes.isEmpty {
                Text("No matching notes")
                    .font(BuoyFont.control)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                    .frame(maxHeight: 300, alignment: .top)
            } else {
                NotesTableViewWrapper(
                    notes: filteredNotes,
                    currentNoteID: currentNoteID,
                    onSelect: { note in
                        onSelect(note)
                        withAnimation(BuoyMotion.easeOut(0.16)) { isShowing = false }
                    },
                    onDelete: onDelete,
                    onTogglePin: onTogglePin,
                    onReorderPinned: onReorderPinned,
                    allowsPinnedReordering: searchText.isEmpty
                )
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 214)
        .background(WindowDragBlocker())
        .buoyGlassPanel(cornerRadius: 14)
        .shadow(radius: 8)
        .transition(BuoyMotion.transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity)))
        .onChange(of: isShowing) { _, showing in
            if !showing { searchText = "" }
        }
    }
}

struct NoteRow: View {
    let note: Note
    let isActive: Bool
    let dragNoteID: String?
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void

    @State private var isHovering = false

    private var title: some View {
        Text(note.title.isEmpty ? "Untitled" : note.title)
            .font(isActive ? BuoyFont.sectionTitle : BuoyFont.control)
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        HStack {
            if let dragNoteID {
                // The drag surface covers the flexible title area (expanded to the row's
                // edges via negative padding), leaving the pin/delete buttons on top of
                // plain SwiftUI so they stay clickable.
                title
                    .background(
                        NoteRowDragHandle(
                            noteID: dragNoteID,
                            onSelect: onSelect
                        )
                            .padding(.vertical, -7)
                            .padding(.leading, -10)
                    )
            } else {
                title
            }

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
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive ? Color.buoySelectionFill : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.1)) { isHovering = h }
        }
        .animation(.easeInOut(duration: 0.1), value: isHovering)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(note.title.isEmpty ? "Untitled" : note.title)
        .accessibilityValue(note.isPinned ? "Pinned" : "")
    }
}
