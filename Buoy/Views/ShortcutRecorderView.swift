import SwiftUI
import AppKit

struct ShortcutRecorderView: View {
    @Binding var shortcut: String
    var onChanged: ((String) -> Void)?

    @State private var isRecording = false
    @State private var flashMessage: String? = nil
    @State private var keyMonitor: Any? = nil
    @State private var flashTask: Task<Void, Never>? = nil

    private let reserved = [
        "Cmd+Space", "Cmd+Tab", "Cmd+Shift+3", "Cmd+Shift+4", "Cmd+Shift+5"
    ]

    private let keycapsWidth: CGFloat = 116
    private let controlsWidth: CGFloat = 118
    private let buttonWidth: CGFloat = 118

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            leftDisplay
                .frame(width: keycapsWidth, height: 34, alignment: .center)

            VStack(spacing: 4) {
                Text("Keyboard Shortcut")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)

                shortcutControl

                Group {
                    if let flashMessage, isRecording {
                        Text(flashMessage)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.9))
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: flashMessage)
            }
            .frame(width: controlsWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { stopRecording() }
    }

    @ViewBuilder
    private var leftDisplay: some View {
        if isRecording {
            ShimmeringShortcutPromptView(text: "Type New...", fontSize: 12.5, minHeight: 30)
                .frame(maxWidth: .infinity, alignment: .center)
                .offset(y: 6)
                .transition(.opacity)
        } else {
            ShortcutKeyCapsView(shortcut: shortcut, keySize: 30, spacing: 5, fontSize: 12.5)
                .frame(maxWidth: .infinity, alignment: .center)
                .offset(y: 6)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var shortcutControl: some View {
        if isRecording {
            Button(action: stopRecording) {
                Text("Cancel")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: buttonWidth)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        } else {
            Button(action: startRecording) {
                Text("Edit")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: buttonWidth)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }

    private func startRecording() {
        flashTask?.cancel()
        flashTask = nil
        flashMessage = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            handleKeyEvent(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        flashMessage = nil
        flashTask?.cancel()
        flashTask = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let mods = event.modifierFlags
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else { return }

        // Escape → cancel
        if event.keyCode == 53 {
            stopRecording()
            return
        }

        let hasMod = mods.contains(.command) || mods.contains(.control) || mods.contains(.option)
        guard hasMod else {
            flash("Needs ⌘/⌃/⌥")
            return
        }

        var parts: [String] = []
        if mods.contains(.control) { parts.append("Ctrl") }
        if mods.contains(.option) { parts.append("Option") }
        if mods.contains(.shift) { parts.append("Shift") }
        if mods.contains(.command) { parts.append("Cmd") }
        parts.append(chars.uppercased())
        let newShortcut = parts.joined(separator: "+")

        if reserved.contains(newShortcut) {
            flash("Reserved!")
            return
        }

        shortcut = newShortcut
        onChanged?(newShortcut)
        stopRecording()
    }

    private func flash(_ msg: String) {
        flashMessage = msg
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            flashMessage = nil
        }
    }
}
