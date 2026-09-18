import SwiftUI
import AppKit

/// One rebindable shortcut in the Settings window: name on the left, key caps
/// and an Edit button on the right.
///
/// The Edit button is a fixed width so the row does not shift when its label
/// swaps to "Cancel", and the key caps are replaced *in place* by the recording
/// prompt so nothing reflows while the user is aiming for a key.
struct ShortcutRecorderRow: View {
    let label: String
    @Binding var shortcut: String
    /// Returns a human phrase naming whatever already owns a combo, or `nil`
    /// when it is free. Buoy's own commands, and macOS's reserved set.
    var conflict: (KeyCombo) -> String?
    var onChanged: (String) -> Void = { _ in }
    var onRecorded: ((KeyCombo) -> Void)? = nil
    @Binding var activeRecording: String?
    /// Marks a row the user has moved off its default.
    var isCustomised: Bool = false

    @State private var isRecording = false
    @State private var flash: String?
    @State private var keyMonitor: Any?
    @State private var flashTask: Task<Void, Never>?

    var body: some View {
        LabeledContent(label) {
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(BuoyTheme.current.accent)
                        .frame(width: 6, height: 6)
                        .opacity(isCustomised && !isRecording ? 1 : 0)
                        .accessibilityHidden(true)
                    display
                        .frame(width: 140, alignment: .trailing)
                    Button(isRecording ? "Cancel" : "Edit") {
                        isRecording ? stopRecording() : startRecording()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 64)
                    .accessibilityLabel(isRecording ? "Cancel recording \(label)" : "Change shortcut for \(label)")
                }
                .frame(width: 230, alignment: .trailing)
                if let flash, isRecording {
                    Text(flash)
                        .font(BuoyFont.caption)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }
            }
            .animation(BuoyMotion.easeInOut(0.15), value: flash)
        }
        .accessibilityValue(ShortcutStrings.symbols(shortcut))
        .onDisappear { stopRecording() }
        .onChange(of: activeRecording) { _, owner in
            if isRecording && owner != label { stopRecording() }
        }
    }

    @ViewBuilder
    private var display: some View {
        if isRecording {
            ShimmeringShortcutPromptView(text: "Type shortcut…", fontSize: 11, minHeight: 24)
        } else {
            ShortcutKeyCapsView(shortcut: shortcut, keySize: 24, spacing: 4, fontSize: 11)
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        activeRecording = label
        // Swallow every key while recording (`return nil`), or the combo the
        // user is typing also fires whatever it is currently bound to.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if activeRecording == label { activeRecording = nil }
        flash = nil
        flashTask?.cancel()
        flashTask = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { stopRecording(); return }

        guard let candidate = KeyCombo(event: event) else {
            showFlash("Needs ⌘, ⌃ or ⌥")
            return
        }
        guard candidate.isSupported else {
            showFlash("Unsupported key")
            return
        }
        if candidate.electronString == shortcut { stopRecording(); return }
        if let owner = conflict(candidate) {
            showFlash("Used by \(owner)")
            return
        }
        if let onRecorded {
            onRecorded(candidate)
        } else {
            shortcut = candidate.electronString
            onChanged(candidate.electronString)
        }
        stopRecording()
    }

    private func showFlash(_ message: String) {
        flash = message
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            flash = nil
        }
    }
}

/// A shortcut Buoy does not let the user change — the standard text-editing
/// keys every Mac app shares. Shown so the page is a complete reference.
struct ShortcutReferenceRow: View {
    let label: String
    let keys: String

    var body: some View {
        LabeledContent {
            Text(keys)
                .font(BuoyFont.secondaryEmphasized)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        } label: {
            // Dimmed to match its keys. A fixed row that looks exactly like an
            // editable one, minus the button, invites a hunt for the button.
            Text(label).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(keys)")
        .accessibilityHint("This shortcut can't be changed")
    }
}
