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
                    .font(BuoyFont.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("This can’t be undone.")
                    .font(BuoyFont.secondary)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .font(BuoyFont.control)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.buoyControlFill, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel("Cancel")
                    .accessibilityHint("Keeps the note. Escape does the same.")
                    .pointingHandCursor()

                Button {
                    onConfirm()
                } label: {
                    HStack(spacing: 5) {
                        Text("Delete")
                            .font(BuoyFont.control.weight(.semibold))
                        Text("⏎")
                            .font(BuoyFont.caption.weight(.semibold))
                            .frame(width: 15, height: 15)
                            .background(Color.buoyOnAccent.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.buoyOnAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .systemRed), in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete")
                .accessibilityHint("Permanently deletes “\(displayTitle)”. Return does the same.")
                .pointingHandCursor()
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 220)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Delete “\(displayTitle)”?")
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.buoyOverlayStroke, lineWidth: 1)
        )
        .shadow(radius: 12, y: 4)
        .transition(BuoyMotion.transition(.scale(scale: 0.9).combined(with: .opacity)))
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
