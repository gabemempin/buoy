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

    @Environment(\.buoyTheme) private var theme

    @State private var isRecording = false
    @State private var flash: String?
    @State private var keyMonitor: Any?
    @State private var flashTask: Task<Void, Never>?

    var body: some View {
        // An explicit row rather than `LabeledContent`. At the popover's width
        // that wrapped the key caps onto a second line under the label, which
        // doubled every row's height and left the page a column of tall,
        // half-empty blocks.
        HStack(spacing: 8) {
            Text(label)
                .font(BuoyFont.control)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 4)

            if isCustomised && !isRecording {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }

            display

            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Cancel" : "Edit")
                    .font(BuoyFont.secondaryEmphasized)
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 22)
                    .contentShape(Capsule())
            }
            .buttonStyle(ShortcutEditButtonStyle(accent: theme.accent))
            .pointingHandCursor()
            // Fixed, so the row does not shift when the label swaps.
            .frame(width: 42, alignment: .trailing)
            .accessibilityLabel(isRecording ? "Cancel recording \(label)" : "Change shortcut for \(label)")
        }
        .frame(height: 22)
        // The conflict message replaces the key caps in place rather than
        // adding a line under them, so nothing reflows while recording.
        .overlay(alignment: .trailing) {
            if let flash, isRecording {
                Text(flash)
                    .font(BuoyFont.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .padding(.trailing, 50)
                    .transition(.opacity)
            }
        }
        .animation(BuoyMotion.easeInOut(0.15), value: flash)
        .accessibilityValue(ShortcutStrings.symbols(shortcut))
        .onDisappear { stopRecording() }
    }

    @ViewBuilder
    private var display: some View {
        if isRecording {
            ShimmeringShortcutPromptView(text: "Type shortcut…", fontSize: 10, minHeight: 20)
                .frame(width: 92)
        } else {
            ShortcutKeyCapsView(shortcut: shortcut, keySize: 20, spacing: 3, fontSize: 10)
                .opacity(flash == nil ? 1 : 0)
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
        HStack(spacing: 8) {
            // Dimmed to match its keys. A fixed row that looks exactly like an
            // editable one, minus the button, invites a hunt for the button.
            Text(label)
                .font(BuoyFont.control)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(keys)
                .font(BuoyFont.secondaryEmphasized)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            // Lines its keys up with the editable rows' key caps, which sit
            // inside a 42pt button lane.
            Color.clear.frame(width: 42, height: 1)
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(keys)")
        .accessibilityHint("This shortcut can't be changed")
    }
}

/// Keep the small label readable even with a bright accent on a matching tint.
private struct ShortcutEditButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(accent.opacity(configuration.isPressed ? 0.30 : 0.12),
                        in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(accent.opacity(0.45), lineWidth: 1)
            }
    }
}
