import AppKit
import SwiftUI

/// Buoy's Settings window.
///
/// Settings used to be a 260pt glass overlay inside the note panel, which set
/// the panel's minimum width, inflated its height while open, and had no room
/// to grow. It is a real window now: a standard titled window with a sidebar,
/// the shape users already know from System Settings.
///
/// Two things about this app make an ordinary window less ordinary than usual.
/// Buoy normally runs as an `.accessory` app, so the window has to activate the
/// app explicitly or it opens behind everything and cannot take keys. And the
/// note panel floats at `.statusBar` level when Always on Top is set, so the
/// settings window has to match that level or the panel covers it.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let store: SettingsStore
    private let model = SettingsWindowModel()

    private let onReportBug: () -> Void
    private let onQuit: () -> Void
    /// Reads the note panel's current level and appearance. A closure rather
    /// than stored copies so the window can never be showing yesterday's theme
    /// because something forgot to push an update.
    private let panelWindowProperties: () -> (level: NSWindow.Level, appearance: NSAppearance?)

    init(
        store: SettingsStore,
        panelWindowProperties: @escaping () -> (level: NSWindow.Level, appearance: NSAppearance?),
        onReportBug: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.store = store
        self.panelWindowProperties = panelWindowProperties
        self.onReportBug = onReportBug
        self.onQuit = onQuit
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Presentation

    func show(page: SettingsPage) {
        model.page = page
        let window = ensureWindow()
        syncWindowProperties()
        // `.accessory` apps get no activation from `makeKeyAndOrderFront`
        // alone, and an unactivated settings window cannot type into the
        // shortcut recorder.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func close(_ sender: Any? = nil) {
        window?.performClose(nil)
    }

    /// Keeps the window's level and appearance in step with the panel's.
    /// Called from `AppDelegate.handleSettingsUpdate`, the same place the panel
    /// gets them, so Always on Top and Theme can never apply to only one.
    func syncWindowProperties() {
        guard let window else { return }
        let properties = panelWindowProperties()
        window.level = properties.level
        window.appearance = properties.appearance
    }

    // MARK: - Window

    private func ensureWindow() -> NSWindow {
        if let window { return window }

        let hosting = NSHostingController(
            rootView: SettingsWindowView(
                store: store,
                model: model,
                onPageChange: { [weak self] page in self?.window?.title = page.title },
                onReportBug: { [weak self] in
                    self?.onReportBug()
                },
                onQuit: onQuit
            )
        )

        let window = SettingsWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsWindowMetrics.contentWidth,
                height: SettingsWindowMetrics.contentHeight
            ),
            // No `.resizable`: every page fits, and a resizable settings window
            // only ever gets dragged to a size that makes the sidebar look wrong.
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = model.page.title
        // The page picker *is* the title bar: the content runs underneath it,
        // the title itself would only repeat what the selected tab already
        // says, and there is no toolbar because nothing else belongs up there.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.setContentSize(
            NSSize(
                width: SettingsWindowMetrics.contentWidth,
                height: SettingsWindowMetrics.contentHeight
            )
        )
        window.setFrameAutosaveName("BuoySettingsWindow")
        if !window.setFrameUsingName("BuoySettingsWindow") {
            centerOverPanel(window)
        }

        self.window = window
        return window
    }

    /// Opens on the screen the panel is on, not whichever screen AppKit thinks
    /// is "main" — on a two-display setup those are routinely different.
    private func centerOverPanel(_ window: NSWindow) {
        let panelScreen = NSApp.windows.first { $0 is BuoyPanel }?.screen
        guard let screen = panelScreen ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            )
        )
    }
}

/// The app is usually `.accessory`, so `NSApp.mainMenu` is not on screen and
/// its key equivalents never fire. ⌘W has to be handled here or the window
/// cannot be closed from the keyboard at all.
private final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .help, .capsLock])
        let key = event.charactersIgnoringModifiers?.lowercased()

        if modifiers == .command, key == "w" {
            performClose(nil)
            return true
        }

        // Keep panel commands from firing while the Settings window is key.
        // Read the registry so their old keys become available after a rebind.
        if ShortcutRegistry.combo(for: .openSettings).matches(event)
            || ShortcutRegistry.combo(for: .harborMode).matches(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
