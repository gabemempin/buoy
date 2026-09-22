import SwiftUI

struct ShortcutsSettingsPage: View {
    @Binding var settings: AppSettings
    @State private var activeRecording: String?

    var body: some View {
        SettingsForm {
            SettingsSection("Show Buoy") {
                ShortcutRecorderRow(
                    label: "Show or hide Buoy",
                    shortcut: $settings.globalShortcut,
                    conflict: { combo in
                        ShortcutRegistry.conflict(for: combo, excluding: nil, isGlobal: true, settings: settings)
                    },
                    activeRecording: $activeRecording,
                    isCustomised: settings.globalShortcut != AppSettings().globalShortcut
                )
            }

            ForEach(BuoyCommand.Group.allCases, id: \.self) { group in
                SettingsSection(group.rawValue) {
                    ForEach(BuoyCommand.allCases.filter { $0.group == group }, id: \.self) { command in
                        commandRow(command)
                    }
                }
            }

            Section {
                ForEach(BuoyCommand.fixed.indices, id: \.self) { index in
                    let item = BuoyCommand.fixed[index]
                    ShortcutReferenceRow(label: item.title, keys: item.keys)
                }
            } header: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .accessibilityHidden(true)
                        Text("Formatting and Editing")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                    Text("These match the shortcuts every Mac app uses and can't be changed.")
                        .font(BuoyFont.secondary)
                        .foregroundStyle(.secondary)
                }
                // Matches `SettingsSection`, which this one cannot use because
                // its header carries a glyph as well as a title.
                .textCase(nil)
                .padding(.bottom, 1)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        activeRecording = nil
                        settings.shortcuts = [:]
                        settings.globalShortcut = AppSettings().globalShortcut
                    }
                    .buttonStyle(.bordered)
                    .disabled(settings.shortcuts.isEmpty && settings.globalShortcut == AppSettings().globalShortcut)
                    .accessibilityLabel("Reset shortcuts to defaults")
                }
            }
        }
        .accessibilityLabel("Keyboard shortcut settings")
    }

    private func commandRow(_ command: BuoyCommand) -> some View {
        ShortcutRecorderRow(
            label: command.title,
            shortcut: Binding(
                get: { (settings.shortcuts[command.rawValue] ?? command.defaultCombo).electronString },
                set: { _ in }
            ),
            conflict: { combo in
                ShortcutRegistry.conflict(for: combo, excluding: command, isGlobal: false, settings: settings)
            },
            onRecorded: { combo in
                var updated = settings.shortcuts
                if combo == command.defaultCombo {
                    updated.removeValue(forKey: command.rawValue)
                } else {
                    updated[command.rawValue] = combo
                }
                settings.shortcuts = updated
            },
            activeRecording: $activeRecording,
            isCustomised: settings.shortcuts[command.rawValue] != nil
        )
    }
}
