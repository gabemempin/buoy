import SwiftUI
import AppKit

struct ShortcutRecorderView: View {
    @Binding var shortcut: String
    var onChanged: ((String) -> Void)?

    @State private var isRecording = false
    @State private var flashMessage: String? = nil
    @State private var keyMonitor: Any? = nil

    private let reserved = [
        "Cmd+Space", "Cmd+Tab", "Cmd+Shift+3", "Cmd+Shift+4", "Cmd+Shift+5"
    ]

    var displayString: String {
        if let flash = flashMessage { return flash }
        if isRecording { return "Press shortcut…" }
        return electronToSymbols(shortcut)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(displayString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                .frame(minWidth: 80, alignment: .center)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Group {
                        if #unavailable(macOS 26) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.07))
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.primary.opacity(0.2), lineWidth: isRecording ? 2 : 1)
                )

            if !isRecording {
                Button("Edit") { startRecording() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button("Cancel") { stopRecording() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            handleKeyEvent(event)
            return nil
        }
        keyMonitor = monitor
    }

    private func stopRecording() {
        isRecording = false
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            flashMessage = nil
        }
    }

    private func electronToSymbols(_ s: String) -> String {
        s.replacingOccurrences(of: "Cmd", with: "⌘")
         .replacingOccurrences(of: "Ctrl", with: "⌃")
         .replacingOccurrences(of: "Option", with: "⌥")
         .replacingOccurrences(of: "Shift", with: "⇧")
         .replacingOccurrences(of: "+", with: "")
    }
}
