import SwiftUI
import AppKit

// MARK: - NSTextField wrapper that explicitly handles ⌘A

private final class TitleNSTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .help, .capsLock])
        if mods == .command && event.keyCode == 0 { // keyCode 0 = "a"
            guard let editor = currentEditor() else {
                return super.performKeyEquivalent(with: event)
            }
            editor.selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct TitleTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var isFocused: Bool
    @Environment(\.colorScheme) var colorScheme

    func makeNSView(context: Context) -> TitleNSTextField {
        let field = TitleNSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: 19, weight: .semibold, width: .expanded)
        field.textColor = NSColor.controlAccentColor
        field.alignment = .center
        field.focusRingType = .none
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submitted(_:))
        return field
    }

    func updateNSView(_ nsView: TitleNSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        nsView.textColor = colorScheme == .dark ? .white : .controlAccentColor
        if isFocused && nsView.window?.firstResponder !== nsView.currentEditor() {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TitleTextField
        init(parent: TitleTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }

        @objc func submitted(_ sender: Any?) { parent.onSubmit() }
    }
}

// MARK: - HeaderView

struct HeaderView: View {
    @Binding var title: String
    /// Toggle this value to auto-focus + select-all the title field (e.g. on new note).
    var focusTitleTrigger: Bool
    var onClose: () -> Void
    var onMinimize: () -> Void
    var onExpand: () -> Void
    var onAllNotes: () -> Void
    var onNewNote: () -> Void
    var focusEditor: () -> Void
    var dragEnabled: Bool = true

    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                TrafficLightsView(onClose: onClose, onMinimize: onMinimize, onExpand: onExpand)
                    .padding(.leading, 12)

                Spacer()

                HStack(spacing: 10) {
                    HeaderButton(systemImage: "line.horizontal.3", tooltip: "All Notes", action: onAllNotes)
                    HeaderButton(systemImage: "plus",              tooltip: "New Note",  action: onNewNote)
                }
                .padding(.trailing, 8)
            }
            .frame(height: 28)
            .padding(.top, 6)

            TitleTextField(
                text: $title,
                placeholder: "Untitled",
                onSubmit: focusEditor,
                isFocused: titleFocused
            )
            .frame(maxWidth: .infinity, minHeight: 26)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .background(dragEnabled ? WindowDragHandle() : nil)
        .onChange(of: focusTitleTrigger) { _, _ in
            titleFocused = true
            DispatchQueue.main.async {
                (NSApp.keyWindow?.firstResponder as? NSText)?.selectAll(nil)
            }
        }
    }
}

private struct HeaderButton: View {
    let systemImage: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(isHovering ? Color.white : Color.white.opacity(0.85))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
                .buoyAccentCircle()
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovering = $0 }
    }
}
