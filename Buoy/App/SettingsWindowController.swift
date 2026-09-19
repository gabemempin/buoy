import AppKit
import SwiftUI
import QuartzCore

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

    /// Opens Settings, or closes it if it is already up.
    ///
    /// The gear is a toggle rather than a one-way door, because a window that
    /// follows the panel around is part of the panel as far as the user is
    /// concerned, and the button that opened it should put it away.
    @discardableResult
    func toggle(page: SettingsPage) -> Bool {
        if isVisible, model.page == page {
            close()
            return false
        }
        show(page: page)
        return true
    }

    func show(page: SettingsPage) {
        model.page = page
        let window = ensureWindow()
        syncWindowProperties()
        attachToPanel(window)

        if !window.isVisible {
            positionAlongsidePanel(window)
            animateOpen(window)
        }

        // `.accessory` apps get no activation from `makeKeyAndOrderFront`
        // alone, and an unactivated settings window cannot type into the
        // shortcut recorder.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func close(_ sender: Any? = nil) {
        guard let window, window.isVisible else { return }
        animateClosed(window)
    }

    // MARK: Following the panel

    /// Makes Settings a child of the note panel.
    ///
    /// Two things fall out of this, both of them what the user asked for. A
    /// child window is dragged along by its parent, so Settings stays beside
    /// the panel wherever the panel goes. And it is always ordered above the
    /// panel, so the floating always-on-top panel can never bury it.
    private func attachToPanel(_ window: NSWindow) {
        guard let panel = NSApp.windows.first(where: { $0 is BuoyPanel }) else { return }
        guard window.parent !== panel else { return }
        panel.addChildWindow(window, ordered: .above)
    }

    /// Opens to the side of the panel with the most room, falling back to the
    /// right. Only used the first time; after that the window keeps wherever
    /// it was left, offset from the panel.
    private func positionAlongsidePanel(_ window: NSWindow) {
        guard let panel = NSApp.windows.first(where: { $0 is BuoyPanel }), panel.isVisible else {
            centerOverPanel(window)
            return
        }
        let gap: CGFloat = 8
        let size = window.frame.size
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let toRight = panel.frame.maxX + gap
        let toLeft = panel.frame.minX - gap - size.width
        let x = (toRight + size.width <= visible.maxX || toLeft < visible.minX) ? toRight : toLeft
        let y = min(
            max(panel.frame.midY - size.height / 2, visible.minY),
            visible.maxY - size.height
        )
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: Open and close

    /// Grows out of the panel rather than appearing on top of it.
    ///
    /// Not the Dock's genie — there is no public API to warp a window along a
    /// curve, and faking it means swapping in a snapshot layer, which flickers.
    /// A scale and fade anchored at the panel's edge reads as the same idea and
    /// is honest about being a window.
    private func animateOpen(_ window: NSWindow) {
        let final = window.frame
        window.setFrame(collapsedFrame(for: final), display: false)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = BuoyMotion.duration(0.26)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(final, display: true)
            window.animator().alphaValue = 1
        }
    }

    private func animateClosed(_ window: NSWindow) {
        let start = window.frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = BuoyMotion.duration(0.2)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(collapsedFrame(for: start), display: true)
            window.animator().alphaValue = 0
        } completionHandler: {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
            // Restored so the next open starts from the right place, and so a
            // frame autosave never records the collapsed size.
            window.setFrame(start, display: false)
            window.alphaValue = 1
        }
    }

    /// The window shrunk toward whichever edge of it faces the panel, so the
    /// motion reads as coming out of the panel rather than out of nowhere.
    private func collapsedFrame(for frame: NSRect) -> NSRect {
        let scale: CGFloat = 0.86
        let size = NSSize(width: frame.width * scale, height: frame.height * scale)
        let panelFrame = NSApp.windows.first { $0 is BuoyPanel }?.frame
        let anchorX: CGFloat
        if let panelFrame, panelFrame.midX > frame.midX {
            anchorX = frame.maxX - size.width
        } else {
            anchorX = frame.minX
        }
        return NSRect(
            x: anchorX,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
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
        // The surface is drawn in SwiftUI so the window can wear Liquid Glass
        // like the note panel. An opaque window would put a flat rectangle
        // behind the material and there would be nothing for it to sample.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentMinSize = NSSize(
            width: SettingsWindowMetrics.minimumContentWidth,
            height: SettingsWindowMetrics.minimumContentHeight
        )
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.setContentSize(
            NSSize(
                width: SettingsWindowMetrics.contentWidth,
                height: SettingsWindowMetrics.contentHeight
            )
        )
        window.setFrameAutosaveName("BuoySettingsWindow3")
        window.setFrameUsingName("BuoySettingsWindow3")

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
