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
    var linkPopover: LinkPopoverPresentation? = nil

    @Environment(\.chromeMetrics) private var metrics

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
            ToolbarPillButton(systemImage: "checklist",   label: "To-Do",         action: onTodo, usesTodoIconSize: true)
            pillDivider
            linkButton
        }
        .clipShape(Capsule())
        .buoyAccentCapsule()
        .padding(.horizontal, metrics.toolbarHorizontalPadding)
        .padding(.vertical, metrics.toolbarVerticalPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
    }

    private var pillDivider: some View {
        Rectangle()
            .fill(Color.buoyOnAccentSeparator)
            .frame(width: 1, height: metrics.toolbarDividerHeight)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var linkButton: some View {
        if let linkPopover {
            ToolbarPillButton(
                systemImage: "link",
                label: "Insert Link",
                shortcut: ShortcutStrings.symbols(ShortcutRegistry.combo(for: .insertLink).electronString),
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
                shortcut: ShortcutStrings.symbols(ShortcutRegistry.combo(for: .insertLink).electronString),
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
    /// The to-do glyph reads smaller than the others at the same point size,
    /// so it takes its own step on the density scale.
    var usesTodoIconSize: Bool = false

    @State private var isHovering = false
    @Environment(\.chromeMetrics) private var metrics

    private var iconSize: CGFloat {
        usesTodoIconSize ? metrics.toolbarTodoIconSize : metrics.toolbarIconSize
    }

    private var tooltip: String {
        shortcut.map { "\(label) (\($0))" } ?? label
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(Color.buoyOnAccent(isProminent: isHovering))
                .frame(width: metrics.toolbarPillWidth, height: metrics.toolbarPillHeight)
                .contentShape(Rectangle())
                .buoyAccentHoverPlate(isHovering: isHovering, cornerRadius: metrics.toolbarPillCornerRadius)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(label)
        .onHover { isHovering = $0 }
    }
}
