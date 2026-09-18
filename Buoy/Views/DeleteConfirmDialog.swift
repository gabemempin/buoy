import SwiftUI
import AppKit

/// Centered confirmation shown before something is deleted.
/// Used by the ⌘⌫ shortcut, the All Notes panel note delete button, and the
/// folder delete button — the copy and icon are parameters so a folder delete
/// can say what it actually does (the notes survive) instead of borrowing the
/// note wording.
struct DeleteConfirmDialog: View {
    let noteTitle: String
    var message: String = "This can’t be undone."
    var confirmTitle: String = "Delete"
    var confirmHint: String?
    var cancelHint: String = "Keeps the note. Escape does the same."
    var iconName: String = "trash"
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
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.red)

            VStack(spacing: 3) {
                Text("Delete “\(displayTitle)”?")
                    .font(BuoyFont.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(message)
                    .font(BuoyFont.secondary)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .font(BuoyFont.control)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.buoyControlFill, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel("Cancel")
                    .accessibilityHint(cancelHint)
                    .pointingHandCursor()

                Button {
                    onConfirm()
                } label: {
                    HStack(spacing: 5) {
                        Text(confirmTitle)
                            .font(BuoyFont.control.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
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
                .accessibilityLabel(confirmTitle)
                .accessibilityHint(
                    confirmHint ?? "Permanently deletes “\(displayTitle)”. Return does the same."
                )
                .pointingHandCursor()
            }
            .padding(.top, 2)
        }
        .padding(16)
        // Wide enough for the longest confirm label ("Delete Folder") beside
        // Cancel. At 220 that button wrapped to two lines and the whole dialog
        // went lopsided.
        //
        // A ceiling rather than a fixed width: the panel's minimum is narrower
        // than 244 now that the Settings overlay no longer props it open, and a
        // fixed width would hang the dialog over both edges of the glass.
        .frame(maxWidth: 244)
        .padding(.horizontal, 8)
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
