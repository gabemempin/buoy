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
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.red)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Delete “\(displayTitle)”?")
                    .font(BuoyFont.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(message)
                    .font(BuoyFont.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)

            // macOS 26+ alerts: capsule buttons of equal width that fill the
            // alert, Cancel leading, the default trailing. The default is the
            // filled one, which is what says Return picks it; the old ⏎
            // keycap inside the label is not something system alerts draw.
            HStack(spacing: 8) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(AlertCapsuleButtonStyle(role: .cancel))
                    .accessibilityHint(cancelHint)

                Button(confirmTitle) { onConfirm() }
                    .buttonStyle(AlertCapsuleButtonStyle(role: .destructive))
                    .accessibilityHint(
                        confirmHint ?? "Permanently deletes “\(displayTitle)”. Return does the same."
                    )
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        // Wide enough for the longest confirm label ("Delete Folder") beside
        // Cancel. At 220 that button wrapped to two lines and the whole dialog
        // went lopsided.
        //
        // A ceiling rather than a fixed width: the panel's minimum is narrower
        // than 244 now that the Settings overlay no longer props it open, and a
        // fixed width would hang the dialog over both edges of the glass.
        .frame(maxWidth: 244)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Delete “\(displayTitle)”?")
        // Concentric with the buttons: the card's radius is the capsule's
        // (half its height) plus the 14pt it sits in from the edge.
        .buoyGlassPanel(cornerRadius: AlertCapsuleButtonStyle.height / 2 + 14)
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        .padding(.horizontal, 8)
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

/// The confirm dialog's buttons, after macOS 26's alerts: full-width
/// capsules, the default one filled. Pressing dims and shrinks it slightly,
/// since a custom button without a press state feels unresponsive (HIG).
private struct AlertCapsuleButtonStyle: ButtonStyle {
    enum Role { case cancel, destructive }

    static let height: CGFloat = 28

    let role: Role
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(role == .destructive ? BuoyFont.control.weight(.semibold) : BuoyFont.control)
            .lineLimit(1)
            .foregroundStyle(role == .destructive ? Color.buoyOnAccent : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background(
                Capsule().fill(role == .destructive ? Color(nsColor: .systemRed) : Color.buoyControlFill)
            )
            .overlay(Capsule().fill(Color.white.opacity(isHovering && !configuration.isPressed ? 0.08 : 0)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .contentShape(Capsule())
            .animation(BuoyMotion.easeOut(0.1), value: configuration.isPressed)
            .onHover { isHovering = $0 }
            .pointingHandCursor()
    }
}
