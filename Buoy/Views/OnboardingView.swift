import SwiftUI
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

// MARK: - OnboardingView

struct OnboardingView: View {
    @Binding var settings: AppSettings
    var onShortcutChanged: (String) -> Void
    var onDismiss: () -> Void

    @State private var currentSlide = 0
    @State private var goingForward = true
    @State private var isDemoMinimized = false
    @State private var cmdMMonitor: Any?
    @Namespace private var indicatorNamespace

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                // Slide content
                ZStack {
                    slideContent
                        .id(currentSlide)
                        .transition(.asymmetric(
                            insertion: .move(edge: goingForward ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .move(edge: goingForward ? .leading : .trailing)
                                .combined(with: .opacity)
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: currentSlide)

                bottomNav
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            cmdMMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if mods == .command && event.keyCode == 46 {
                    NotificationCenter.default.post(name: .onboardingCmdM, object: nil)
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let m = cmdMMonitor { NSEvent.removeMonitor(m); cmdMMonitor = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingCmdM)) { _ in
            guard currentSlide == 2 else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isDemoMinimized.toggle()
            }
        }
    }

    @ViewBuilder
    private var slideContent: some View {
        switch currentSlide {
        case 0:
            WelcomeSlide(settings: $settings, onShortcutChanged: onShortcutChanged)
        case 1:
            FormattingSlide()
        case 2:
            HarborModeSlide(
                isDemoMinimized: isDemoMinimized,
                onToggleDemo: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isDemoMinimized.toggle()
                    }
                }
            )
        case 3:
            BugReportSlide()
        default:
            EmptyView()
        }
    }

    private var bottomNav: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i == currentSlide ? Color.accentColor : Color.primary.opacity(0.2))
                        .frame(width: i == currentSlide ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: currentSlide)

            Button {
                if currentSlide < 3 {
                    goingForward = true
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        currentSlide += 1
                    }
                } else {
                    complete()
                }
            } label: {
                Text(currentSlide < 3 ? "Next" : "Get Started")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .environment(\.controlActiveState, .active)
            .shadow(color: Color.accentColor.opacity(0.32), radius: 4, y: 2)

            Button("Back") {
                guard currentSlide > 0 else { return }
                goingForward = false
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    currentSlide -= 1
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .opacity(currentSlide > 0 ? 1 : 0)
            .allowsHitTesting(currentSlide > 0)
            .animation(.easeInOut(duration: 0.18), value: currentSlide)
        }
        .padding(.top, 2)
        .padding(.bottom, 20)
    }

    private func complete() {
        settings.onboarded = true
        settings.save()
        onDismiss()
    }
}

private extension Notification.Name {
    static let onboardingCmdM = Notification.Name("BuoyOnboardingCmdM")
}

private func loadOnboardingAppIconThumbnail() async -> NSImage? {
    guard
        let iconManifestURL = Bundle.main.url(forResource: "icon", withExtension: "json"),
        let floatLayerURL = Bundle.main.url(forResource: "Float", withExtension: "png"),
        let notepadLayerURL = Bundle.main.url(forResource: "Notepad", withExtension: "png")
    else {
        return nil
    }

    let fileManager = FileManager.default
    let iconURL = fileManager.temporaryDirectory.appendingPathComponent(
        "BuoyOnboardingAppIcon.icon",
        isDirectory: true
    )
    let assetsURL = iconURL.appendingPathComponent("Assets", isDirectory: true)

    do {
        try? fileManager.removeItem(at: iconURL)
        try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: iconManifestURL, to: iconURL.appendingPathComponent("icon.json"))
        try fileManager.copyItem(at: floatLayerURL, to: assetsURL.appendingPathComponent("Float.png"))
        try fileManager.copyItem(at: notepadLayerURL, to: assetsURL.appendingPathComponent("Notepad.png"))
    } catch {
        return nil
    }

    let request = QLThumbnailGenerator.Request(
        fileAt: iconURL,
        size: CGSize(width: 512, height: 512),
        scale: NSScreen.main?.backingScaleFactor ?? 2,
        representationTypes: .thumbnail
    )
    request.contentType = UTType(importedAs: "com.apple.iconcomposer.icon")
    request.iconMode = false

    do {
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<NSImage?, Error>) in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                representation, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: representation?.nsImage)
                }
            }
        }
    } catch {
        return nil
    }
}

// MARK: - Slide 1: Welcome

private struct WelcomeSlide: View {
    @Binding var settings: AppSettings
    var onShortcutChanged: (String) -> Void

    @State private var onboardingAppIcon: NSImage?
    @State private var iconAppeared = false
    @State private var titleAppeared = false
    @State private var keyCapsAppeared = false
    @State private var hintAppeared = false
    @State private var isEditingShortcut = false
    @State private var shortcutFlashMessage: String?
    @State private var shortcutMonitor: Any?
    @State private var shortcutFlashTask: Task<Void, Never>?

    private let reservedShortcuts = [
        "Cmd+Space", "Cmd+Tab", "Cmd+Shift+3", "Cmd+Shift+4", "Cmd+Shift+5"
    ]

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Group {
                    if let onboardingAppIcon {
                        Image(nsImage: onboardingAppIcon)
                            .interpolation(.high)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 80, height: 80)
                .shadow(radius: 4)
                .scaleEffect(iconAppeared ? 1.0 : 0.72)
                .opacity(iconAppeared ? 1 : 0)
                .offset(y: iconAppeared ? 0 : 8)

                VStack(spacing: 6) {
                    Text("Welcome to Buoy")
                        .font(.system(size: 22, weight: .bold))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.accentColor)
                        .multilineTextAlignment(.center)
                    Text("A notepad that floats on top of all your windows.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .opacity(titleAppeared ? 1 : 0)
                .offset(y: titleAppeared ? 0 : 8)

                VStack(spacing: 10) {
                    ZStack {
                        if isEditingShortcut {
                            ShortcutRecordingPrompt(text: "Type your new shortcut…")
                                .padding(.top, 16)
                                .transition(.opacity)
                        } else {
                            KeyCapsView(shortcut: settings.globalShortcut, triggerPress: keyCapsAppeared)
                                .padding(.top, 16)
                                .transition(.opacity)
                        }
                    }
                    .frame(minHeight: 50)
                    .animation(.easeInOut(duration: 0.18), value: isEditingShortcut)

                    Group {
                        if let shortcutFlashMessage, isEditingShortcut {
                            Text(shortcutFlashMessage)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Color.red.opacity(0.9))
                                .transition(.opacity)
                        } else {
                            Color.clear.frame(height: 13)
                        }
                    }
                    .frame(minHeight: 13)
                    .animation(.easeInOut(duration: 0.15), value: shortcutFlashMessage)

                    if isEditingShortcut {
                        Button("Cancel") { stopShortcutEditing() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                    } else {
                        Button("Edit") { startShortcutEditing() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .opacity(keyCapsAppeared ? 1 : 0)
                .offset(y: keyCapsAppeared ? 0 : 8)

                Text("You can change this any time in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .opacity(hintAppeared ? 1 : 0)
                    .offset(y: hintAppeared ? 0 : 8)
            }
            .frame(maxWidth: 288)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .task {
            if onboardingAppIcon == nil {
                onboardingAppIcon = await loadOnboardingAppIconThumbnail()
            }
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.spring(response: 0.52, dampingFraction: 0.7)) { iconAppeared = true }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.52, dampingFraction: 0.7)) { titleAppeared = true }
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.52, dampingFraction: 0.7)) { keyCapsAppeared = true }
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.52, dampingFraction: 0.7)) { hintAppeared = true }
        }
        .onDisappear {
            stopShortcutEditing()
        }
    }

    private func startShortcutEditing() {
        shortcutFlashTask?.cancel()
        shortcutFlashTask = nil
        shortcutFlashMessage = nil
        isEditingShortcut = true

        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }

        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            handleShortcutKeyEvent(event)
            return nil
        }
    }

    private func stopShortcutEditing() {
        isEditingShortcut = false
        shortcutFlashMessage = nil
        shortcutFlashTask?.cancel()
        shortcutFlashTask = nil
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
    }

    private func handleShortcutKeyEvent(_ event: NSEvent) {
        let mods = event.modifierFlags
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
            return
        }

        if event.keyCode == 53 {
            stopShortcutEditing()
            return
        }

        let hasModifier = mods.contains(.command) || mods.contains(.control) || mods.contains(.option)
        guard hasModifier else {
            flashShortcutMessage("Needs ⌘/⌃/⌥")
            return
        }

        var parts: [String] = []
        if mods.contains(.control) { parts.append("Ctrl") }
        if mods.contains(.option) { parts.append("Option") }
        if mods.contains(.shift) { parts.append("Shift") }
        if mods.contains(.command) { parts.append("Cmd") }
        parts.append(chars.uppercased())
        let newShortcut = parts.joined(separator: "+")

        if reservedShortcuts.contains(newShortcut) {
            flashShortcutMessage("Reserved!")
            return
        }

        settings.globalShortcut = newShortcut
        onShortcutChanged(newShortcut)
        settings.save()
        stopShortcutEditing()
    }

    private func flashShortcutMessage(_ message: String) {
        shortcutFlashTask?.cancel()
        shortcutFlashMessage = message
        shortcutFlashTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            shortcutFlashMessage = nil
        }
    }
}

// MARK: - Skeumorphic Key Caps

private struct KeyCapsView: View {
    let shortcut: String
    var triggerPress: Bool = false
    @State private var pressedIndex: Int? = nil
    @State private var hasPressed = false

    private var parts: [String] {
        shortcut.components(separatedBy: "+").map { part in
            switch part {
            case "Option": return "⌥"
            case "Cmd":    return "⌘"
            case "Ctrl":   return "⌃"
            case "Shift":  return "⇧"
            default:       return part.uppercased()
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, label in
                KeyCapView(label: label, isPressed: pressedIndex == index)
            }
        }
        .onChange(of: triggerPress) { _, newVal in
            guard newVal, !hasPressed else { return }
            hasPressed = true
            let count = parts.count
            for i in 0..<count {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(i * 60))
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        pressedIndex = i
                    }
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        if pressedIndex == i { pressedIndex = nil }
                    }
                }
            }
        }
    }
}

private struct KeyCapView: View {
    let label: String
    var isPressed: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Base key body
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(.sRGB, red: 0.26, green: 0.26, blue: 0.30, opacity: 1),
                           Color(.sRGB, red: 0.14, green: 0.14, blue: 0.17, opacity: 1)]
                        : [Color.white, Color(.sRGB, white: 0.91, opacity: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.65 : 0.22), radius: 0, x: 0, y: 3)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 6, x: 0, y: 4)

            // Top highlight
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(colorScheme == .dark ? 0.14 : 0.80), .clear],
                    startPoint: .top,
                    endPoint: .center
                ))
                .padding(1.5)

            // Outer border
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.10),
                    lineWidth: 1
                )

            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color(.sRGB, white: 0.18, opacity: 1))
        }
        .frame(width: 50, height: 50)
        .scaleEffect(isPressed ? 0.92 : 1.0, anchor: .center)
        .offset(y: isPressed ? 1 : 0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
    }
}

// MARK: - Slide 2: Formatting

private final class DemoTextViewRef {
    var value: BuoyTextView?
}

private struct FormattingSlide: View {
    @State private var demoRTFData: Data = Self.templateRTF()
    @State private var demoTVRef = DemoTextViewRef()
    @State private var headerAppeared = false
    @State private var panelAppeared = false
    @State private var subheadingAppeared = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            slideHeader("Format your thoughts")
                .opacity(headerAppeared ? 1 : 0)
                .offset(y: headerAppeared ? 0 : 8)

            MiniEditorPanel(
                rtfData: $demoRTFData,
                tvRef: demoTVRef,
                usesDarkAppearance: colorScheme == .dark
            )
            .frame(maxWidth: 280)
            .padding(.horizontal, 16)
            .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
            .opacity(panelAppeared ? 1 : 0)
            .scaleEffect(panelAppeared ? 1 : 0.96, anchor: .center)
            .offset(y: panelAppeared ? 0 : 8)

            slideSubheading(
                "Bold, italic, bullets, todos, links —\nall with keyboard shortcuts."
            )
            .padding(.bottom, 2)
            .opacity(subheadingAppeared ? 1 : 0)
            .offset(y: subheadingAppeared ? 0 : 8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .onAppear {
            DispatchQueue.main.async {
                guard let tv = demoTVRef.value, let storage = tv.textStorage else { return }
                // Find " and to do lists" and prepend a live TodoAttachment before it
                let fullString = storage.string
                guard let markerRange = fullString.range(of: " and to do lists") else { return }
                let insertLocation = NSRange(markerRange, in: fullString).location
                let todo = TodoAttachment(isChecked: false, displaySize: CGSize(width: 15, height: 15), yOffset: -2)
                let attachStr = NSAttributedString(attachment: todo)
                storage.beginEditing()
                storage.insert(attachStr, at: insertLocation)
                storage.endEditing()
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.spring(response: 0.52, dampingFraction: 0.7)) { headerAppeared = true }
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.spring(response: 0.52, dampingFraction: 0.7)) { panelAppeared = true }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.spring(response: 0.52, dampingFraction: 0.7)) { subheadingAppeared = true }
        }
    }

    static func templateRTF() -> Data {
        let size: CGFloat = 13
        let regular = NSFont.systemFont(ofSize: size)

        let boldDesc = regular.fontDescriptor.withSymbolicTraits(.bold)
        let bold = NSFont(descriptor: boldDesc, size: size) ?? regular

        let italicDesc = regular.fontDescriptor.withSymbolicTraits(.italic)
        let italic = NSFont(descriptor: italicDesc, size: size) ?? regular

        let s = NSMutableAttributedString()

        func add(_ text: String, font: NSFont = regular, extras: [NSAttributedString.Key: Any] = [:]) {
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            for (k, v) in extras { attrs[k] = v }
            s.append(NSAttributedString(string: text, attributes: attrs))
        }

        add("• ")
        add("Bold", font: bold)
        add(", ")
        add("italic", font: italic)
        add(", ")
        add("underline", extras: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        add("\n• Bullet points\n and to do lists")

        let range = NSRange(location: 0, length: s.length)
        return (try? s.data(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtf
        ])) ?? Data()
    }
}

private struct MiniEditorPanel: View {
    @Binding var rtfData: Data
    var tvRef: DemoTextViewRef
    var usesDarkAppearance: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Title row
            VStack(spacing: 3) {
                HStack {
                    MiniTrafficLights()
                        .padding(.leading, 10)
                    Spacer()
                }
                .frame(height: 22)
                .padding(.top, 5)

                Text("Test it here!")
                    .font(.system(size: 16, weight: .semibold))
                    .fontWidth(.expanded)
                    .foregroundStyle(usesDarkAppearance ? Color.white : Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 3)
            }

            // Formatting pill
            DemoToolbarView(tvRef: tvRef)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            // Editor
            EditorView(
                rtfData: rtfData,
                fontSize: 13,
                usesDarkAppearance: usesDarkAppearance,
                noteID: "onboarding-demo",
                placeholder: "Try typing and formatting!",
                onContentChange: { rtfData = $0 },
                textViewRef: { tvRef.value = $0 }
            )
            .frame(height: 100)
        }
        .buoyGlassPanel(cornerRadius: 16)
    }
}

private struct DemoToolbarView: View {
    var tvRef: DemoTextViewRef

    var body: some View {
        ToolbarView(
            onBold:      { applyFormat { $0.applyBold() } },
            onItalic:    { applyFormat { $0.applyItalic() } },
            onUnderline: { applyFormat { $0.applyUnderline() } },
            onBullet:    { applyCursorAction { $0.applyBullet($1) } },
            onTodo:      { applyCursorAction { $0.applyTodo($1) } },
            onLink:      {}
        )
    }

    private func applyFormat(_ action: @escaping (BuoyTextView) -> Void) {
        guard let tv = tvRef.value else { return }
        tv.window?.makeFirstResponder(tv)
        DispatchQueue.main.async {
            if tv.lastKnownSelection.length > 0 {
                tv.setSelectedRange(tv.lastKnownSelection)
            }
            action(tv)
        }
    }

    private func applyCursorAction(_ action: @escaping (BuoyTextView, NSRange) -> Void) {
        guard let tv = tvRef.value else { return }
        let pos = tv.lastKnownCursorPosition
        tv.window?.makeFirstResponder(tv)
        DispatchQueue.main.async { action(tv, pos) }
    }
}

// MARK: - Slide 3: Harbor Mode

private struct HarborModeSlide: View {
    var isDemoMinimized: Bool
    var onToggleDemo: () -> Void
    @State private var hasTriggeredOnce = false

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            slideHeader("Harbor Mode")

            ZStack {
                if isDemoMinimized {
                    MinimizedNotePillView(
                        title: "My note",
                        theme: .system,
                        onRestore: onToggleDemo
                    )
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
                    .transition(.scale(scale: 0.88, anchor: .bottom).combined(with: .opacity))
                } else {
                    HarborModeDemoPanel()
                        .transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: 300)
            .padding(.horizontal, 20)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isDemoMinimized)

            Group {
                if hasTriggeredOnce || isDemoMinimized {
                    Text(isDemoMinimized ? "Press ⌘M again to restore" : "Press ⌘M to try it")
                } else {
                    let hintText = "Press ⌘M to try it"
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let cycle = t.truncatingRemainder(dividingBy: 1.6) / 1.6
                        let phase = sin(cycle * .pi * 2 - .pi / 2)
                        let opacity = 0.55 + 0.45 * (1.0 + phase) / 2.0
                        Text(hintText).opacity(opacity)
                    }
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
            .animation(.easeInOut(duration: 0.2), value: isDemoMinimized)
            .onChange(of: isDemoMinimized) { _, newVal in
                if newVal { hasTriggeredOnce = true }
            }

            slideSubheading(
                "Click the minimize button or press ⌘M\nto tuck Buoy away without closing."
            )
            .padding(.bottom, 2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

private struct HarborModeDemoPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                HStack {
                    MiniTrafficLights()
                        .padding(.leading, 10)
                    Spacer()
                }
                .frame(height: 22)
                .padding(.top, 5)

                Text("My note")
                    .font(.system(size: 16, weight: .semibold))
                    .fontWidth(.expanded)
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 3)
            }

            ToolbarView(
                onBold: {}, onItalic: {}, onUnderline: {},
                onBullet: {}, onTodo: {}, onLink: {},
                isBugReport: false
            )
            .allowsHitTesting(false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Color.clear.frame(height: 14)
        }
        .buoyGlassPanel(cornerRadius: 16)
        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
    }
}

// MARK: - Slide 4: Bug Report

private struct BugReportSlide: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            slideHeader("Thanks for testing")

            BugReportDemoPanel()
                .frame(maxWidth: 280)
                .padding(.horizontal, 16)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 5)

            slideSubheading(
                "Use \"Report a Bug\" in Settings to send\nfeedback directly from the app."
            )
            .padding(.bottom, 2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

private struct BugReportDemoPanel: View {
    var body: some View {
        VStack(spacing: 0) {
            // Title row
            VStack(spacing: 3) {
                HStack {
                    MiniTrafficLights()
                        .padding(.leading, 10)
                    Spacer()
                }
                .frame(height: 22)
                .padding(.top, 5)

                // Shimmer title — reuses the real AnimatedBugTitle
                AnimatedBugTitle(title: "Bug Report")
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 3)
            }

            // Blue toolbar pill (non-interactive)
            ToolbarView(
                onBold: {}, onItalic: {}, onUnderline: {},
                onBullet: {}, onTodo: {}, onLink: {},
                isBugReport: true
            )
            .allowsHitTesting(false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Placeholder body
            Text("Tell me what you want fixed or improved…")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.22))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .buoyGlassPanel(cornerRadius: 16)
    }
}

// MARK: - Shared helpers

private struct MiniTrafficLights: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color(red: 1.0, green: 0.37, blue: 0.34))
                .frame(width: 10, height: 10)
                .padding(.horizontal, 4)
            Circle()
                .fill(Color(red: 0.99, green: 0.74, blue: 0.18))
                .frame(width: 10, height: 10)
                .padding(.horizontal, 4)
            Circle()
                .fill(Color(red: 0.16, green: 0.78, blue: 0.25))
                .frame(width: 10, height: 10)
                .padding(.horizontal, 4)
        }
    }
}

@ViewBuilder
private func slideHeader(_ text: String) -> some View {
    SlideHeaderText(text: text)
}

@ViewBuilder
private func slideSubheading(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
}

private struct SlideHeaderText: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .bold))
            .fontWidth(.expanded)
            .multilineTextAlignment(.center)
            .foregroundStyle(colorScheme == .dark ? Color.primary : Color.accentColor)
            .padding(.horizontal, 8)
    }
}

private struct ShortcutRecordingPrompt: View {
    let text: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            frame(phase: Self.phase(for: timeline.date))
        }
        .frame(maxWidth: .infinity, minHeight: 50)
    }

    private static func phase(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.0) / 2.0)
    }

    private func frame(phase: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .overlay {
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .mask {
                        GeometryReader { geo in
                            Ellipse()
                                .fill(Color.white)
                                .frame(width: 96, height: geo.size.height + 16)
                                .blur(radius: 14)
                                .offset(x: phase * (geo.size.width + 176) - 88)
                        }
                    }
            }
            .foregroundStyle(Color.primary.opacity(0.4))
    }
}

// MARK: - Onboarding Background

private struct OnboardingBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: PanelLayoutMetrics.onboardingCornerRadius)
            .fill(colorScheme == .dark
                ? Color(.sRGB, white: 0.11, opacity: 1)
                : Color.white
            )
    }
}
