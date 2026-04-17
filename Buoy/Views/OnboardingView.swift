import SwiftUI
import AppKit

// MARK: - OnboardingView

struct OnboardingView: View {
    @Binding var settings: AppSettings
    var onShortcutChanged: (String) -> Void
    var onDismiss: () -> Void

    @State private var currentSlide = 0
    @State private var goingForward = true
    @State private var isDemoMinimized = false
    @State private var cmdMMonitor: Any?

    var body: some View {
        ZStack {
            Color.clear
                .buoyInsetGlass(
                    inset: PanelLayoutMetrics.onboardingInset,
                    cornerRadius: PanelLayoutMetrics.onboardingCornerRadius
                )

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
            if currentSlide == 0 {
                HStack {
                    Spacer()
                    skipButton
                    Spacer()
                }
                .padding(.horizontal, 24)
            } else {
                HStack {
                    if currentSlide > 0 {
                        Button("Back") {
                            goingForward = false
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                currentSlide -= 1
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    } else {
                        Color.clear.frame(width: 32, height: 14)
                    }

                    Spacer()

                    if currentSlide < 3 {
                        skipButton
                    } else {
                        Color.clear.frame(width: 32, height: 14)
                    }
                }
                .padding(.horizontal, 24)
            }

            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i == currentSlide ? Color.accentColor : Color.primary.opacity(0.2))
                        .frame(
                            width: i == currentSlide ? 8 : 6,
                            height: i == currentSlide ? 8 : 6
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentSlide)
                }
            }

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
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    private var skipButton: some View {
        Button("Skip") { complete() }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
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

// MARK: - Slide 1: Welcome

private struct WelcomeSlide: View {
    @Binding var settings: AppSettings
    var onShortcutChanged: (String) -> Void

    @State private var iconAppeared = false
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
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(radius: 4)
                        .scaleEffect(iconAppeared ? 1.0 : 0.72)
                        .opacity(iconAppeared ? 1 : 0)
                }

                VStack(spacing: 6) {
                    Text("Welcome to Buoy")
                        .font(.system(size: 22, weight: .bold))
                        .fontWidth(.expanded)
                        .multilineTextAlignment(.center)
                    Text("A notepad that floats on top of all your windows.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                VStack(spacing: 10) {
                    ZStack {
                        if isEditingShortcut {
                            ShortcutRecordingPrompt(text: "Type your new shortcut…")
                                .transition(.opacity)
                        } else {
                            KeyCapsView(shortcut: settings.globalShortcut)
                                .padding(.top, 2)
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

                Text("You can change this any time in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: 288)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.spring(response: 0.52, dampingFraction: 0.7)) {
                iconAppeared = true
            }
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
            ForEach(Array(parts.enumerated()), id: \.offset) { _, label in
                KeyCapView(label: label)
            }
        }
    }
}

private struct KeyCapView: View {
    let label: String

    var body: some View {
        ZStack {
            // Base key body
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(
                    colors: [
                        Color(.sRGB, red: 0.26, green: 0.26, blue: 0.30, opacity: 1),
                        Color(.sRGB, red: 0.14, green: 0.14, blue: 0.17, opacity: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                // Physical bottom-shelf shadow
                .shadow(color: .black.opacity(0.65), radius: 0, x: 0, y: 3)
                // Ambient glow
                .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 4)

            // Top highlight
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.14), .clear],
                    startPoint: .top,
                    endPoint: .center
                ))
                .padding(1.5)

            // Outer border
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)

            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 50, height: 50)
    }
}

// MARK: - Slide 2: Formatting

private final class DemoTextViewRef {
    var value: BuoyTextView?
}

private final class DemoTodoCircleAttachment: NSTextAttachment {
    init(size: CGFloat = 13) {
        super.init(data: nil, ofType: nil)
        let image = NSImage(size: CGSize(width: size, height: size), flipped: false) { rect in
            let circle = rect.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(ovalIn: circle)
            NSColor.secondaryLabelColor.setStroke()
            path.lineWidth = 1.35
            path.stroke()
            return true
        }
        self.image = image
        self.bounds = CGRect(x: 0, y: -1.5, width: size, height: size)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

private struct FormattingSlide: View {
    @State private var demoRTFData: Data = Self.templateRTF()
    @State private var demoTVRef = DemoTextViewRef()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            slideHeader("Format Your Thoughts")

            MiniEditorPanel(
                rtfData: $demoRTFData,
                tvRef: demoTVRef,
                usesDarkAppearance: colorScheme == .dark
            )
            .frame(maxWidth: 280)
            .padding(.horizontal, 16)
            .shadow(color: .black.opacity(0.18), radius: 14, y: 5)

            slideSubheading(
                "Bold, italic, bullets, todos, links —\nall with keyboard shortcuts."
            )
            .padding(.bottom, 2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
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
        add("\n• Bullet points\n")
        s.append(NSAttributedString(attachment: DemoTodoCircleAttachment()))
        add(" and to do lists")

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
                    .transition(.scale(scale: 0.88, anchor: .bottom).combined(with: .opacity))
                } else {
                    HarborModeDemoPanel()
                        .transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: 300)
            .padding(.horizontal, 20)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isDemoMinimized)

            Text(isDemoMinimized ? "Press ⌘M again to restore" : "Press ⌘M to try it →")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .animation(.easeInOut(duration: 0.2), value: isDemoMinimized)

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

            slideHeader("Help Us Improve")

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
