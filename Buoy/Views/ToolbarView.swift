import SwiftUI
import AppKit

struct LinkPopoverPresentation {
    let isPresented: Binding<Bool>
    let content: () -> AnyView
}

struct ToolbarView: View {
    var onBold: () -> Void
    var onItalic: () -> Void
    var onUnderline: () -> Void
    var onStrikethrough: () -> Void
    var onBullet: () -> Void
    var onTodo: () -> Void
    var onLink: () -> Void
    var isBugReport: Bool = false
    var linkPopover: LinkPopoverPresentation? = nil

    var body: some View {
        HStack(spacing: 0) {
            ToolbarPillButton(systemImage: "bold",        label: "Bold",          shortcut: "⌘B",  action: onBold)
            pillDivider
            ToolbarPillButton(systemImage: "italic",      label: "Italic",        shortcut: "⌘I",  action: onItalic)
            pillDivider
            ToolbarPillButton(systemImage: "underline",   label: "Underline",     shortcut: "⌘U",  action: onUnderline)
            pillDivider
            ToolbarPillButton(systemImage: "strikethrough", label: "Strikethrough", shortcut: "⌘⇧X", action: onStrikethrough)
            pillDivider
            ToolbarPillButton(systemImage: "list.bullet", label: "Bullet List",   action: onBullet)
            pillDivider
            ToolbarPillButton(systemImage: "checklist",   label: "To-Do",         action: onTodo, iconSize: 15)
            pillDivider
            linkButton
        }
        .clipShape(Capsule())
        .buoyAccentCapsule(color: isBugReport ? .blue : .accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
    }

    private var pillDivider: some View {
        Rectangle()
            .fill(Color.buoyOnAccentSeparator)
            .frame(width: 1, height: 14)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var linkButton: some View {
        if let linkPopover {
            ToolbarPillButton(
                systemImage: "link",
                label: "Insert Link",
                shortcut: "⌘K",
                action: onLink
            )
            .popover(
                isPresented: linkPopover.isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                linkPopover.content()
            }
        } else {
            ToolbarPillButton(
                systemImage: "link",
                label: "Insert Link",
                shortcut: "⌘K",
                action: onLink
            )
        }
    }
}

private struct ToolbarPillButton: View {
    let systemImage: String
    /// Spoken name. Kept separate from the tooltip so VoiceOver announces
    /// "Bold" rather than reading the key equivalent out as part of the name.
    let label: String
    var shortcut: String? = nil
    let action: () -> Void
    var iconSize: CGFloat = 12

    @State private var isHovering = false

    private var tooltip: String {
        shortcut.map { "\(label) (\($0))" } ?? label
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(Color.buoyOnAccent(isProminent: isHovering))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
                .buoyAccentHoverPlate(isHovering: isHovering, cornerRadius: 7)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(label)
        .onHover { isHovering = $0 }
    }
}
