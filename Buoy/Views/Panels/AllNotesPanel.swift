import SwiftUI

struct AllNotesPanel: View {
    @Binding var isShowing: Bool
    var notes: [Note]
    var currentNoteID: String?
    var onSelect: (Note) -> Void
    var onDelete: (Note) -> Void

    @State private var searchText = ""

    private var filteredNotes: [Note] {
        if searchText.isEmpty { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || Self.plainTextContent(from: $0.contentRTF)
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    private static func plainTextContent(from rtfData: Data) -> String {
        guard !rtfData.isEmpty else { return "" }
        guard let attributed = try? NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else {
            return ""
        }
        return attributed.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("All Notes")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { isShowing = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
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
                    .font(.system(size: 12))
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
                        withAnimation(.easeOut(duration: 0.16)) { isShowing = false }
                    },
                    onDelete: onDelete
                )
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 214)
        .background(WindowDragBlocker())
        .overlay(ArrowCursorOverlay().allowsHitTesting(false))
        .buoyGlassPanel(cornerRadius: 14)
        .shadow(radius: 8)
        .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
        .onChange(of: isShowing) { _, showing in
            if !showing { searchText = "" }
        }
    }
}

struct NoteRow: View {
    let note: Note
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isActive ? Color.primary.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.1)) { isHovering = h }
        }
        .animation(.easeInOut(duration: 0.1), value: isHovering)
    }
}
