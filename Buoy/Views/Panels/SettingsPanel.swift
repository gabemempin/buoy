import SwiftUI
import AppKit
import LaunchAtLogin

struct SettingsPanel: View {
    @Environment(\.colorScheme) private var colorScheme
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
                    withAnimation(BuoyMotion.easeOut(0.16)) { isShowing = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.buoyControlFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Settings")
                .pointingHandCursor()
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 14)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                SettingsToggle(label: "Show in Dock", isOn: $settings.showInDock)
                    .onChange(of: settings.showInDock) { _, val in
                        NSApp.setActivationPolicy(val ? .regular : .accessory)
                        if val { NSApp.activate(ignoringOtherApps: true) }
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
                            .accessibilityLabel("Editor font size")
                            .accessibilityValue("\(Int(settings.fontSize)) points")
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
                            .font(BuoyFont.secondary)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                            .accessibilityHidden(true)
                    }
                }

                SettingsRow(label: "Theme") {
                    ThemeSegmentedPicker(selection: $settings.theme)
                        .onChange(of: settings.theme) { _, _ in settings.save() }
                }

                Divider().padding(.horizontal, 10).padding(.vertical, 4)

                ShortcutRecorderView(shortcut: $settings.globalShortcut) { newShortcut in
                    onShortcutChanged(newShortcut)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

                Divider().padding(.horizontal, 10).padding(.vertical, 9)

                VStack(spacing: 6) {
                    Button { onReportBug() } label: {
                        Label("Report a Bug", systemImage: "ladybug")
                            .font(BuoyFont.control)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .buoySettingsActionButton(
                                tint: .orange,
                                role: .accent,
                                isHovering: isReportBugHovering,
                                fillOpacity: isReportBugHovering ? 0.12 : 0.08,
                                strokeOpacity: isReportBugHovering ? 0.62 : 0.46
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(reportBugForegroundColor)
                    .onHover { isReportBugHovering = $0 }
                    .accessibilityLabel("Report a Bug")
                    .pointingHandCursor()

                    Button { checkForUpdates() } label: {
                        Group {
                            if let status = updateStatus { Text(status) }
                            else { Text("Check for Updates") }
                        }
                        .font(BuoyFont.control)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .buoySettingsActionButton(tint: .gray, role: .neutral, isHovering: isCheckUpdatesHovering)
                    }
                    .buttonStyle(.plain)
                    .onHover { isCheckUpdatesHovering = $0 }
                    .accessibilityLabel("Check for Updates")
                    .accessibilityValue(updateStatus ?? "")
                    .pointingHandCursor()

                    Button("Quit Buoy") { onQuit() }
                        .font(BuoyFont.control)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .buoySettingsActionButton(tint: .red, role: .destructive, isHovering: isQuitHovering)
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                        .onHover { isQuitHovering = $0 }
                        .pointingHandCursor()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 260)
        .background(WindowDragBlocker())
        .buoyGlassPanel(cornerRadius: 14)
        .shadow(radius: 8)
        .transition(BuoyMotion.transition(.scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity)))
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

    private var reportBugForegroundColor: Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.76, blue: 0.42)
            : Color(red: 0.76, green: 0.36, blue: 0.03)
    }
}

// MARK: - Subviews

private struct SettingsToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(BuoyFont.control)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                // The visible label is a sibling Text, so the switch itself
                // reaches VoiceOver unnamed without this.
                .accessibilityLabel(label)
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
                .font(BuoyFont.control)
                .foregroundStyle(.secondary)
            Spacer()
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

private struct ThemeSegmentedPicker: View {
    @Binding var selection: AppTheme
    private let options: [(String, AppTheme)] = [("Auto", .system), ("Light", .light), ("Dark", .dark)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.1) { label, theme in
                Button {
                    selection = theme
                } label: {
                    Text(label)
                        .font(BuoyFont.secondaryEmphasized)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background {
                            if selection == theme {
                                Capsule()
                                    .fill(Color.buoySegmentSelection)
                            }
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == theme ? Color.primary : Color.secondary)
                .accessibilityLabel(label)
                .accessibilityAddTraits(selection == theme ? [.isButton, .isSelected] : .isButton)
                .pointingHandCursor()
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.buoySegmentTrack))
        .animation(.easeInOut(duration: 0.15), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme")
    }
}

private enum BuoySettingsActionRole {
    case accent
    case neutral
    case destructive
}

private extension View {
    func buoySettingsActionButton(
        tint: Color,
        role: BuoySettingsActionRole,
        isHovering: Bool,
        cornerRadius: CGFloat = 18,
        fillOpacity: Double? = nil,
        strokeOpacity: Double? = nil
    ) -> some View {
        let fillColor: Color
        let baseStrokeOpacity: Double
        switch role {
        case .accent:
            fillColor = tint.opacity(fillOpacity ?? (isHovering ? 0.20 : 0.14))
            baseStrokeOpacity = strokeOpacity ?? (isHovering ? 0.52 : 0.34)
        case .neutral:
            fillColor = Color.black.opacity(fillOpacity ?? (isHovering ? 0.09 : 0.06))
            baseStrokeOpacity = strokeOpacity ?? (isHovering ? 0.52 : 0.34)
        case .destructive:
            fillColor = tint.opacity(fillOpacity ?? (isHovering ? 0.16 : 0.10))
            baseStrokeOpacity = strokeOpacity ?? (isHovering ? 0.52 : 0.34)
        }

        return self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(tint.opacity(baseStrokeOpacity), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isHovering ? 0.08 : 0.04), radius: isHovering ? 8 : 4, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .animation(.easeInOut(duration: 0.16), value: isHovering)
    }
}
