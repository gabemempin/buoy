import SwiftUI
import AppKit

struct ToolbarView: View {
    var onBold: () -> Void
    var onItalic: () -> Void
    var onUnderline: () -> Void
    var onBullet: () -> Void
    var onTodo: () -> Void
    var onLink: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ToolbarPillButton(systemImage: "bold",        tooltip: "Bold (⌘B)",        action: onBold)
            pillDivider
            ToolbarPillButton(systemImage: "italic",      tooltip: "Italic (⌘I)",      action: onItalic)
            pillDivider
            ToolbarPillButton(systemImage: "underline",   tooltip: "Underline (⌘U)",   action: onUnderline)
            pillDivider
            ToolbarPillButton(systemImage: "list.bullet", tooltip: "Bullet List",       action: onBullet)
            pillDivider
            ToolbarPillButton(systemImage: "checklist",   tooltip: "To-Do",             action: onTodo, iconSize: 15)
            pillDivider
            ToolbarPillButton(systemImage: "link",        tooltip: "Insert Link (⌘K)", action: onLink)
        }
        .floatNotesAccentCapsule()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var pillDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.3))
            .frame(width: 1, height: 14)
    }
}

private struct ToolbarPillButton: View {
    let systemImage: String
    let tooltip: String
    let action: () -> Void
    var iconSize: CGFloat = 12

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(isHovering ? Color.white : Color.white.opacity(0.85))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovering = $0 }
    }
}
