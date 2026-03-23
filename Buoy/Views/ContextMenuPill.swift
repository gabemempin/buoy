import SwiftUI
import AppKit

/// A floating pill panel that appears near the text selection offering formatting buttons.
/// Runs in a separate NSPanel to preserve text selection state.
final class ContextMenuPillController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ContextMenuPillView>?
    weak var textView: BuoyTextView?

    func show(near rect: NSRect, in parentWindow: NSWindow) {
        guard let tv = textView else { return }

        let pill = ContextMenuPillView(
            onBold: { tv.applyBold() },
            onItalic: { tv.applyItalic() },
            onUnderline: { tv.applyUnderline() },
            onLink: {
                let sel = tv.selectedRange()
                let text = sel.length > 0 ? (tv.string as NSString).substring(with: sel) : ""
                NotificationCenter.default.post(name: .showLinkDialog, object: text)
            },
            onDismiss: { [weak self] in self?.hide() }
        )

        let hosting = NSHostingView(rootView: pill)
        hosting.frame = NSRect(x: 0, y: 0, width: 170, height: 36)

        if panel == nil {
            let p = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .floating
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = hosting
            panel = p
            hostingView = hosting
        } else {
            panel?.contentView = hosting
            hostingView = hosting
        }

        // Position above selection rect (in screen coordinates)
        var screenRect = parentWindow.convertToScreen(rect)
        let pillSize = NSSize(width: 170, height: 36)
        screenRect.origin.x = screenRect.midX - pillSize.width / 2
        screenRect.origin.y = screenRect.maxY + 6

        panel?.setFrameOrigin(screenRect.origin)
        panel?.setContentSize(pillSize)
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

// MARK: - SwiftUI View

struct ContextMenuPillView: View {
    var onBold: () -> Void
    var onItalic: () -> Void
    var onUnderline: () -> Void
    var onLink: () -> Void
    var onDismiss: () -> Void

    @State private var dismissTask: Task<Void, Never>? = nil

    var body: some View {
        HStack(spacing: 2) {
            PillButton(label: "B", font: .system(size: 13, weight: .bold),  action: { onBold(); onDismiss() })
            PillButton(label: "I", font: .system(size: 13).italic(),         action: { onItalic(); onDismiss() })
            PillButton(label: "U", font: .system(size: 13),                  action: { onUnderline(); onDismiss() })

            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 18)
                .padding(.horizontal, 2)

            Button(action: { onLink(); onDismiss() }) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .floatNotesGlass(material: .popover)
        .clipShape(Capsule())
        .shadow(radius: 6)
        .onHover { hovering in
            // 200ms safety delay — prevents accidental dismissal on slight cursor movements
            if !hovering {
                dismissTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    onDismiss()
                }
            } else {
                dismissTask?.cancel()
                dismissTask = nil
            }
        }
    }
}

private struct PillButton: View {
    let label: String
    let font: Font
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .foregroundStyle(Color.primary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}
