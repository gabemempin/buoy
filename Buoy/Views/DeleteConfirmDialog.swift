import SwiftUI
import AppKit

/// Centered confirmation shown before a note is permanently deleted.
/// Used by both the ⌘⌫ shortcut and the All Notes panel delete button.
struct DeleteConfirmDialog: View {
    let noteTitle: String
    var onCancel: () -> Void
    var onConfirm: () -> Void

    /// The panel is non-activating and the editor keeps first responder, so
    /// SwiftUI's `.defaultAction`/`.cancelAction` shortcuts never fire here.
    /// A local monitor intercepts Return/Escape and consumes the event so the
    /// keystroke can't leak into the (blurred) text view behind the dialog.
    @State private var keyMonitor: Any?

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
                    .pointingHandCursor()

                Button {
                    onConfirm()
                } label: {
                    HStack(spacing: 5) {
                        Text("Delete")
                            .font(.system(size: 12, weight: .semibold))
                        Text("⏎")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 15, height: 15)
                            .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
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
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 36, 76: // Return, keypad Enter
                onConfirm()
                return nil
            case 53: // Escape
                onCancel()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
