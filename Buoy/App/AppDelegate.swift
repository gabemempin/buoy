import AppKit
import SwiftUI
import Sparkle
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: BuoyPanel?
    private var hostingView: NSHostingView<ContentView>?
    private var statusItem: NSStatusItem?
    private var updaterController: SPUStandardUpdaterController?

    let noteStore = NoteStore()
    var settings = AppSettings.load()

    private let compactHeight: CGFloat = 520
    private let expandedHeight: CGFloat = 780
    private var isExpanded = false
    private var currentHeight: CGFloat = 520
    private var hasPositioned = false

    // MARK: - App Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activation policy
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)

        // Apply saved theme
        applyTheme(settings.theme)

        // Sparkle
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Build panel
        setupPanel()

        // Status bar item
        setupStatusItem()

        // Global hotkey
        HotkeyService.shared.register(shortcut: settings.globalShortcut)
        HotkeyService.shared.onToggle = { [weak self] in
            self?.togglePanel()
        }

        // Observe settings changes for always-on-top
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsUpdate),
            name: .settingsDidChange,
            object: nil
        )

        // Native menus
        buildMainMenu()

        // Show on launch
        showPanel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        noteStore.flushPendingSaves()
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        let contentView = ContentView(
            noteStore: noteStore,
            settings: settingsBinding(),
            updaterController: updaterController,
            onHeightChange: { [weak self] h in
                self?.animateHeight(h, allowShrink: false)
            },
            onClose: { [weak self] in self?.hidePanel() },
            onMinimize: { [weak self] in self?.panel?.miniaturize(nil) },
            onExpand: { [weak self] in self?.toggleExpand() }
        )

        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = NSRect(
            x: 0,
            y: 0,
            width: max(380, PanelLayoutMetrics.minimumWindowWidth),
            height: compactHeight
        )
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        let p = BuoyPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: max(380, PanelLayoutMetrics.minimumWindowWidth),
                height: compactHeight
            ),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = settings.alwaysOnTop ? .statusBar : .normal
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
        currentHeight = compactHeight
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }

        // Use colored icon (not template)
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
        menu.addItem(withTitle: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
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

    func animateHeight(_ newHeight: CGFloat, allowShrink: Bool) {
        guard let p = panel else { return }
        let target = max(PanelLayoutMetrics.minimumWindowHeight, min(700, newHeight))
        guard allowShrink || target > currentHeight else { return }
        currentHeight = target
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setContentSize(NSSize(width: p.frame.width, height: target))
        }
    }

    // MARK: - Menu Actions

    @objc private func openSettings() {
        showPanel()
        // Settings panel opened via ContentView state (post notification)
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    @objc private func checkForUpdates() {
        updaterController?.updater.checkForUpdates()
    }

    @objc private func handleSettingsUpdate() {
        panel?.level = settings.alwaysOnTop ? .statusBar : .normal
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
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
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
            get: { self.settings },
            set: { self.settings = $0 }
        )
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("Buoy2OpenSettings")
}
