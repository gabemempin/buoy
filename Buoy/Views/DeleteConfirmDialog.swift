import SwiftUI

/// Centered confirmation shown before a note is permanently deleted.
/// Used by both the ⌘⌫ shortcut and the All Notes panel delete button.
struct DeleteConfirmDialog: View {
    let noteTitle: String
    var onCancel: () -> Void
    var onConfirm: () -> Void

    private var displayTitle: String {
        let trimmed = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.red)

            VStack(spacing: 3) {
                Text("Delete “\(displayTitle)”?")
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("This can’t be undone.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .keyboardShortcut(.cancelAction)

                Button("Delete") { onConfirm() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 7))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(radius: 12, y: 4)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}
