import SwiftUI

struct ShortcutsSettingsPage: View {
    @Binding var settings: AppSettings
    var onShortcutChanged: (String) -> Void

    var body: some View {
        SettingsForm {
            Section("Show Buoy") {
                ShortcutRecorderRow(
                    label: "Show or hide Buoy",
                    shortcut: $settings.globalShortcut,
                    conflict: conflict(for:),
                    onChanged: onShortcutChanged,
                    isCustomised: settings.globalShortcut != AppSettings().globalShortcut
                )
            }

            Section("Notes") {
                ShortcutReferenceRow(label: "New Note", keys: "⌘N")
                ShortcutReferenceRow(label: "Delete Note", keys: "⌘⌫")
                ShortcutReferenceRow(label: "Copy Note", keys: "⌘⏎")
                ShortcutReferenceRow(label: "Previous Note", keys: "⌘←")
                ShortcutReferenceRow(label: "Next Note", keys: "⌘→")
            }

            Section("Editing") {
                ShortcutReferenceRow(label: "Insert Link", keys: "⌘K")
            }

            Section("Window") {
                ShortcutReferenceRow(label: "Harbor Mode", keys: "⌘M")
                ShortcutReferenceRow(label: "Settings", keys: "⌘,")
                ShortcutReferenceRow(label: "Hide Buoy", keys: "⌘W")
            }

            Section("Formatting") {
                ShortcutReferenceRow(label: "Bold", keys: "⌘B")
                ShortcutReferenceRow(label: "Italic", keys: "⌘I")
                ShortcutReferenceRow(label: "Underline", keys: "⌘U")
                ShortcutReferenceRow(label: "Strikethrough", keys: "⌘⇧X")
            }
        }
        .accessibilityLabel("Keyboard shortcut settings")
    }

    private func conflict(for candidate: String) -> String? {
        ShortcutStrings.systemReserved.contains(candidate) ? "macOS" : nil
    }
}
