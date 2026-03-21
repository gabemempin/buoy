import SwiftUI

struct AllNotesPanel: View {
    @Binding var isShowing: Bool
    var notes: [Note]
    var currentNoteID: String?
    var onSelect: (Note) -> Void
    var onDelete: (Note) -> Void

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
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Note list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(notes) { note in
                        NoteRow(
                            note: note,
                            isActive: note.id == currentNoteID,
                            onSelect: {
                                onSelect(note)
                                withAnimation(.easeOut(duration: 0.16)) { isShowing = false }
                            },
                            onDelete: { onDelete(note) }
                        )
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 214)
        .background(WindowDragBlocker())
        .floatNotesGlassPanel(cornerRadius: 14)
        .shadow(radius: 8)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity),
                removal: .scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity)
            )
        )
    }
}

private struct NoteRow: View {
    let note: Note
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            Button(action: onSelect) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isActive ? Color.primary.opacity(0.08) : Color.clear)
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.1)) { isHovering = h }
        }
        .animation(.easeInOut(duration: 0.1), value: isHovering)
    }
}
