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
    /// Draws the buttons for formats at the caret pressed in. Read here, not
    /// in `ContentView`, so a caret move re-renders only the toolbar.
    var formattingState: EditorFormattingState? = nil
    /// The link key latches only while a link popover is open, rather than
    /// whenever the caret is inside a link.
    var isLinkDialogOpen: Bool = false

    @Environment(\.chromeMetrics) private var metrics

    private func isActive(_ format: EditorFormattingState.Format) -> Bool {
        formattingState?.contains(format) == true
    }

    var body: some View {
        HStack(spacing: 0) {
            ToolbarPillButton(systemImage: "bold",        label: "Bold",          shortcut: "⌘B",  isActive: isActive(.bold), position: .leading, action: onBold)
            pillDivider
            ToolbarPillButton(systemImage: "italic",      label: "Italic",        shortcut: "⌘I",  isActive: isActive(.italic), action: onItalic)
            pillDivider
            ToolbarPillButton(systemImage: "underline",   label: "Underline",     shortcut: "⌘U",  isActive: isActive(.underline), action: onUnderline)
            pillDivider
            ToolbarPillButton(systemImage: "strikethrough", label: "Strikethrough", shortcut: "⌘⇧X", isActive: isActive(.strikethrough), action: onStrikethrough)
            pillDivider
            ToolbarPillButton(systemImage: "list.bullet", label: "Bullet List",   isActive: isActive(.bullet), action: onBullet)
            pillDivider
            ToolbarPillButton(systemImage: "checklist",   label: "To-Do",         isActive: isActive(.todo), action: onTodo, usesTodoIconSize: true)
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

    /// The seam between two keys: full height, a shadowed groove with a
    /// catch of light on its trailing side, like the gap between the keys
    /// of a tape deck.
    private var pillDivider: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color.black.opacity(0.22))
            Rectangle().fill(Color.white.opacity(0.14))
        }
        .frame(width: 1, height: metrics.toolbarPillHeight)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var linkButton: some View {
        if let linkPopover {
            ToolbarPillButton(
                systemImage: "link",
                label: "Insert Link",
                shortcut: ShortcutStrings.symbols(ShortcutRegistry.combo(for: .insertLink).electronString),
                isActive: isLinkDialogOpen,
                position: .trailing,
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
                isActive: isLinkDialogOpen,
                position: .trailing,
                action: onLink
            )
        }
    }
}

/// Where a key sits in the pill: the end keys take the capsule's round ends.
private enum ToolbarKeyPosition {
    case leading, middle, trailing
}

private struct ToolbarPillButton: View {
    let systemImage: String
    /// Spoken name. Kept separate from the tooltip so VoiceOver announces
    /// "Bold" rather than reading the key equivalent out as part of the name.
    let label: String
    var shortcut: String? = nil
    /// The format is on at the caret: the key stays pressed into the pill.
    var isActive: Bool = false
    var position: ToolbarKeyPosition = .middle
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
                .font(.system(size: iconSize, weight: isActive ? .semibold : .regular))
                .foregroundStyle(Color.buoyOnAccent(isProminent: isHovering || isActive))
                // Sunk into the deck: a touch smaller, but still centred
                // in its key.
                .scaleEffect(isActive ? 0.92 : 1)
                .frame(width: metrics.toolbarPillWidth, height: metrics.toolbarPillHeight)
                .contentShape(Rectangle())
                .background(
                    ToolbarKeyFace(
                        isActive: isActive,
                        isHovering: isHovering,
                        position: position,
                        endRadius: metrics.toolbarPillHeight / 2
                    )
                )
                .animation(BuoyMotion.spring(response: 0.2, dampingFraction: 0.75), value: isActive)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .onHover { isHovering = $0 }
    }
}

/// One key of the formatting bar, after the transport keys of a tape deck:
/// each key fills its slot edge to edge, between full-height seams, and the
/// end keys follow the pill's round ends.
///
/// At rest a key is faintly raised, lit along its top edge and shaded at
/// its foot. Latched (the format is on) it sinks: a darker face, a deep
/// shadow cast down from the top edge and in from the sides, and light
/// catching the lip at the bottom.
private struct ToolbarKeyFace: View {
    let isActive: Bool
    let isHovering: Bool
    let position: ToolbarKeyPosition
    let endRadius: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: position == .leading ? endRadius : 0,
            bottomLeadingRadius: position == .leading ? endRadius : 0,
            bottomTrailingRadius: position == .trailing ? endRadius : 0,
            topTrailingRadius: position == .trailing ? endRadius : 0,
            style: .continuous
        )
    }

    var body: some View {
        ZStack {
            // Raised: light on top, shade at the foot.
            shape
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(isHovering ? 0.2 : 0.1), .clear, .black.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(isActive ? 0 : 1)

            // Sunk.
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            .black.opacity(contrast == .increased ? 0.42 : 0.32),
                            .black.opacity(contrast == .increased ? 0.26 : 0.16)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .shadow(.inner(color: .black.opacity(0.55), radius: 3, x: 0, y: 2.5))
                    .shadow(.inner(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 0))
                )
                .overlay(
                    shape
                        .inset(by: 0.5)
                        .stroke(
                            LinearGradient(
                                colors: [.clear, .clear, .white.opacity(0.28)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .opacity(isActive ? 1 : 0)
        }
        .accessibilityHidden(true)
    }
}
