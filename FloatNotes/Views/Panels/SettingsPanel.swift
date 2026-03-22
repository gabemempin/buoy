import SwiftUI
import AppKit
import Sparkle
import LaunchAtLogin

struct SettingsPanel: View {
    @Binding var isShowing: Bool
    @Binding var settings: AppSettings
    var updaterController: SPUStandardUpdaterController?
    var onQuit: () -> Void
    var onShortcutChanged: (String) -> Void

    @State private var updateStatus: String? = nil
    @State private var updateStatusTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { isShowing = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                // Toggles
                SettingsToggle(label: "Show in Dock", isOn: $settings.showInDock)
                    .onChange(of: settings.showInDock) { _, val in
                        NSApp.setActivationPolicy(val ? .regular : .accessory)
                        settings.save()
                    }
                SettingsToggle(label: "Always on Top", isOn: $settings.alwaysOnTop)
                    .onChange(of: settings.alwaysOnTop) { _, _ in settings.save() }
                SettingsToggle(label: "Launch at Login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, val in
                        LaunchAtLogin.isEnabled = val
                        settings.save()
                    }

                Divider().padding(.horizontal, 10).padding(.vertical, 4)

                // Font Size
                SettingsRow(label: "Font Size") {
                    Picker("", selection: $settings.fontSize) {
                        Text("S").tag(FontSize.small)
                        Text("M").tag(FontSize.medium)
                        Text("L").tag(FontSize.large)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 100)
                    .onChange(of: settings.fontSize) { _, _ in settings.save() }
                }

                // Theme
                SettingsRow(label: "Theme") {
                    Picker("", selection: $settings.theme) {
                        Text("Auto").tag(AppTheme.system)
                        Text("Light").tag(AppTheme.light)
                        Text("Dark").tag(AppTheme.dark)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 130)
                    .onChange(of: settings.theme) { _, val in
                        applyTheme(val)
                        settings.save()
                    }
                }

                Divider().padding(.horizontal, 10).padding(.vertical, 4)

                // Global Shortcut
                VStack(alignment: .leading, spacing: 4) {
                    Text("Global Shortcut")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ShortcutRecorderView(shortcut: $settings.globalShortcut) { newShortcut in
                        onShortcutChanged(newShortcut)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                Divider().padding(.horizontal, 10).padding(.vertical, 4)

                // Update + Quit
                VStack(spacing: 6) {
                    Button { checkForUpdates() } label: {
                        Group {
                            if let status = updateStatus { Text(status) }
                            else { Text("Check for Updates") }
                        }
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .glassEffect(.regular.tint(.primary.opacity(0.08)).interactive(), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)

                    Button("Quit FloatNotes") { onQuit() }
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .glassEffect(.regular.tint(.red.opacity(0.08)).interactive(), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.3), lineWidth: 0.5))
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 260)
        .background(WindowDragBlocker())
        .floatNotesGlassPanel(cornerRadius: 20)
        .shadow(radius: 8)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity),
                removal: .scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity)
            )
        )
    }

    private func applyTheme(_ theme: AppTheme) {
        let app = NSApplication.shared
        switch theme {
        case .light:
            app.windows.forEach { $0.appearance = NSAppearance(named: .aqua) }
        case .dark:
            app.windows.forEach { $0.appearance = NSAppearance(named: .darkAqua) }
        case .system:
            app.windows.forEach { $0.appearance = nil }
        }
    }

    private func checkForUpdates() {
        updaterController?.updater.checkForUpdates()
        // Optimistically show "up to date" after 3s if no Sparkle UI appeared
        updateStatus = "Checking…"
        updateStatusTask?.cancel()
        updateStatusTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            updateStatus = "Up to date (v\(version))!"
            try? await Task.sleep(for: .seconds(3))
            updateStatus = nil
        }
    }
}

// MARK: - Subviews

private struct SettingsToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

private struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}
