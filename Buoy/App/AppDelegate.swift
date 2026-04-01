import AppKit
import SwiftUI
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: BuoyPanel?
    private var hostingView: NSHostingView<ContentView>?
    private var statusItem: NSStatusItem?

    let noteStore = NoteStore()
    var settingsStore = SettingsStore()

    private let compactHeight: CGFloat = PanelLayoutMetrics.minimumWindowHeight
    private let onboardingHeight: CGFloat = 520
    private let expandedHeight: CGFloat = 780
    private var isExpanded = false
    private var currentHeight: CGFloat = PanelLayoutMetrics.minimumWindowHeight
    private var hasPositioned = false

    // MARK: - App Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(settingsStore.value.showInDock ? .regular : .accessory)
        applyTheme(settingsStore.value.theme)
        setupPanel()
        setupStatusItem()
        HotkeyService.shared.register(shortcut: settingsStore.value.globalShortcut)
        HotkeyService.shared.onToggle = { [weak self] in self?.togglePanel() }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsUpdate),
            name: .settingsDidChange,
            object: nil
        )
        buildMainMenu()
        showPanel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        noteStore.flushPendingSaves()
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        let isFirstRun = !settingsStore.value.onboarded
        let initialHeight = isFirstRun ? onboardingHeight : compactHeight

        let contentView = ContentView(
            noteStore: noteStore,
            settings: settingsBinding(),
            onHeightChange: { [weak self] h in
                self?.animateHeight(h, allowShrink: false)
            },
            onNoteSwitchHeight: { [weak self] h in
                self?.animateHeight(h, allowShrink: true, duration: 0.50, timingName: .easeInEaseOut)
            },
            onOnboardingComplete: { [weak self] in
                self?.animateOnboardingDismiss()
            },
            onClose: { [weak self] in self?.hidePanel() },
            onMinimize: { [weak self] in self?.panel?.miniaturize(nil) },
            onExpand: { [weak self] in self?.toggleExpand() }
        )

        let initialWidth = PanelLayoutMetrics.minimumWindowWidth
        let initialRect = NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight)

        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = initialRect
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        let p = BuoyPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = settingsStore.value.alwaysOnTop ? .statusBar : .normal
        p.isOpaque = false
        p.backgroundColor = .clear
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.minSize = NSSize(
            width: PanelLayoutMetrics.minimumWindowWidth,
            height: PanelLayoutMetrics.minimumWindowHeight
        )
        p.contentView = hosting

        panel = p
        hostingView = hosting
        currentHeight = initialHeight
    }

    private func animateOnboardingDismiss() {
        guard let p = panel else { return }
        let targetWidth = PanelLayoutMetrics.minimumWindowWidth
        let targetHeight = compactHeight
        let currentFrame = p.frame
        let widthDiff = currentFrame.width - targetWidth
        let heightDiff = currentFrame.height - targetHeight
        let newFrame = NSRect(
            x: currentFrame.minX + widthDiff / 2,
            y: currentFrame.minY + heightDiff / 2,
            width: targetWidth,
            height: targetHeight
        )
        currentHeight = targetHeight
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.55
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            p.animator().setFrame(newFrame, display: true)
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }

        if let icon = NSImage(named: "MenuBarIcon") {
            icon.isTemplate = false
            button.image = icon
        } else {
            // Fallback: pencil SF symbol
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Buoy")?
                .withSymbolConfiguration(config)
        }

        button.target = self
        button.action = #selector(statusButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Buoy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Panel Show/Hide

    @objc func togglePanel() {
        guard let p = panel else { return }
        if p.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let p = panel else { return }
        if !hasPositioned {
            p.center()
            hasPositioned = true
        }
        p.makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        panel?.orderOut(nil)
    }

    func toggleExpand() {
        isExpanded.toggle()
        animateHeight(isExpanded ? expandedHeight : compactHeight, allowShrink: true)
    }

    func animateHeight(
        _ newHeight: CGFloat,
        allowShrink: Bool,
        duration: CGFloat = 0.15,
        timingName: CAMediaTimingFunctionName = .easeOut
    ) {
        guard let p = panel else { return }
        let target = max(PanelLayoutMetrics.minimumWindowHeight, min(PanelLayoutMetrics.maximumAutoHeight, newHeight))
        guard allowShrink || target > currentHeight else { return }
        currentHeight = target
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: timingName)
            p.animator().setContentSize(NSSize(width: p.frame.width, height: target))
        }
    }

    // MARK: - Menu Actions

    @objc private func openSettings() {
        showPanel()
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    @objc private func handleSettingsUpdate() {
        panel?.level = settingsStore.value.alwaysOnTop ? .statusBar : .normal
    }

    // MARK: - Theme

    func applyTheme(_ theme: AppTheme) {
        let appearance: NSAppearance?
        switch theme {
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        case .system: appearance = nil
        }
        panel?.appearance = appearance
    }

    // MARK: - Main Menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Buoy", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Buoy", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Buoy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Window menu
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
    }
}

// MARK: - Bindings helper for AppDelegate

extension AppDelegate {
    func settingsBinding() -> Binding<AppSettings> {
        Binding(
            get: { self.settingsStore.value },
            set: { self.settingsStore.value = $0 }
        )
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("Buoy2OpenSettings")
}
