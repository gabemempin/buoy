import SwiftUI

struct ShortcutsPanel: View {
    @Binding var isShowing: Bool
    var globalShortcut: String

    private let shortcuts: [(key: String, action: String)] = [
        ("⌘B", "Bold"),
        ("⌘I", "Italic"),
        ("⌘U", "Underline"),
        ("⌘K", "Insert Link"),
        ("⌘N", "New Note"),
        ("⌘⌫", "Delete Note"),
        ("⌘⏎", "Copy to Clipboard"),
        ("⌘←", "Previous Note"),
        ("⌘→", "Next Note"),
        ("⌘M", "Harbor Mode"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
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
                .accessibilityLabel("Close Keyboard Shortcuts")
                .pointingHandCursor()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            VStack(spacing: 0) {
                ShortcutRow(key: globalShortcut, action: "Toggle Buoy")
                Divider().padding(.horizontal, 10)

                ForEach(shortcuts, id: \.key) { s in
                    ShortcutRow(key: s.key, action: s.action)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 248)
        .background(WindowDragBlocker())
        .buoyGlassPanel(cornerRadius: 14)
        .shadow(radius: 8)
        .transition(BuoyMotion.transition(.scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity)))
    }
}

private struct ShortcutRow: View {
    let key: String
    let action: String

    var body: some View {
        HStack {
            Text(action)
                .font(BuoyFont.secondary)
                .foregroundStyle(.secondary)
            Spacer()
            Text(key)
                .font(BuoyFont.secondaryEmphasized)
                .foregroundStyle(.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.buoyControlFill)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        // Announced as one phrase; the two Texts read as unrelated fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(action), \(key)")
    }
}
