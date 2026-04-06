import SwiftUI
import AppKit
import LaunchAtLogin

struct SettingsPanel: View {
    @Binding var isShowing: Bool
    @Binding var settings: AppSettings
    var onQuit: () -> Void
    var onShortcutChanged: (String) -> Void
    var onReportBug: () -> Void

    @State private var updateStatus: String? = nil
    @State private var updateStatusTask: Task<Void, Never>? = nil
    @State private var isReportBugHovering = false
    @State private var isCheckUpdatesHovering = false
    @State private var isQuitHovering = false

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
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
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

                SettingsRow(label: "Font Size") {
                    HStack(spacing: 6) {
                        Slider(value: $settings.fontSize, in: 11...20, step: 1)
                            .frame(width: 100)
                            .background {
                                GeometryReader { geo in
                                    let inset: CGFloat = 9
                                    let x = inset + (3.0 / 9.0) * (geo.size.width - inset * 2)
                                    Circle()
                                        .fill(Color.primary.opacity(0.65))
                                        .frame(width: 3, height: 3)
                                        .position(x: x, y: geo.size.height - 1)
                                }
                                .allowsHitTesting(false)
                            }
                        Text("\(Int(settings.fontSize))pt")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                    }
                }

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
                        settings.save()
                    }
                }

                Divider().padding(.horizontal, 10).padding(.vertical, 4)

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

                VStack(spacing: 6) {
                    Button { onReportBug() } label: {
                        Label("Report a Bug", systemImage: "ladybug")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .buoyGlassButton(tint: .orange, strokeOpacity: 0.6, isHovering: isReportBugHovering)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange.opacity(0.9))
                    .onHover { isReportBugHovering = $0 }

                    Button { checkForUpdates() } label: {
                        Group {
                            if let status = updateStatus { Text(status) }
                            else { Text("Check for Updates") }
                        }
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .buoyGlassButton(tint: .primary, tintOpacity: 0.08, strokeOpacity: 0.15, isHovering: isCheckUpdatesHovering)
                    }
                    .buttonStyle(.plain)
                    .onHover { isCheckUpdatesHovering = $0 }

                    Button("Quit Buoy") { onQuit() }
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .buoyGlassButton(tint: .red, strokeOpacity: 0.6, isHovering: isQuitHovering)
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                        .onHover { isQuitHovering = $0 }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 260)
        .background(WindowDragBlocker())
        .overlay(ArrowCursorOverlay().allowsHitTesting(false))
        .buoyGlassPanel(cornerRadius: 20)
        .shadow(radius: 8)
        .transition(.scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity))
    }

    private func checkForUpdates() {
        updateStatus = "Checking…"
        updateStatusTask?.cancel()
        updateStatusTask = Task { @MainActor in
            let result = await UpdateService.shared.checkForUpdates()
            switch result {
            case .upToDate(let version):
                updateStatus = "Up to date (v\(version))!"
            case .available(let version, let url):
                updateStatus = "v\(version) available — click to install"
                NSWorkspace.shared.open(url)
            case .error:
                updateStatus = "Couldn't check for updates"
            }
            try? await Task.sleep(for: .seconds(4))
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
