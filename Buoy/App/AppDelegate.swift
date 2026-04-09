import AppKit
import SwiftUI
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: BuoyPanel?
    private var hostingView: NSHostingView<ContentView>?
    private var statusItem: NSStatusItem?
    private var minimizeRestoreMenuItem: NSMenuItem?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    let noteStore = NoteStore()
    var settingsStore = SettingsStore()
    let panelPresentation = PanelPresentationModel()

    private let compactHeight: CGFloat = PanelLayoutMetrics.minimumWindowHeight
    private let onboardingWidth: CGFloat = 360
    private let onboardingHeight: CGFloat = 520
    private let expandedHeight: CGFloat = 780
    private var currentHeight: CGFloat = PanelLayoutMetrics.minimumWindowHeight
    private var overlayOverrideHeight: CGFloat = 0
    private var hasPositioned = false
    private var lastFullSizeFrame: NSRect?
    private var isMinimizeAnimating = false

    private func panelContentHeight(_ panel: NSPanel) -> CGFloat {
        panel.contentRect(forFrameRect: panel.frame).height
    }

    private func panelContentSize(_ panel: NSPanel) -> NSSize {
        panel.contentRect(forFrameRect: panel.frame).size
    }

    private func frame(
        forContentSize contentSize: NSSize,
        preservingTopOf currentFrame: NSRect,
        in panel: NSPanel
    ) -> NSRect {
        let currentContentRect = panel.contentRect(forFrameRect: currentFrame)
        let targetContentRect = NSRect(origin: currentContentRect.origin, size: contentSize)
        var targetFrame = panel.frameRect(forContentRect: targetContentRect)
        targetFrame.origin.x = currentFrame.origin.x
        targetFrame.origin.y = currentFrame.maxY - targetFrame.height
        return targetFrame
    }

    private func centeredFrame(
        forContentSize contentSize: NSSize,
        around currentFrame: NSRect,
        in panel: NSPanel
    ) -> NSRect {
        let targetFrame = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        )
        return NSRect(
            x: currentFrame.midX - targetFrame.width / 2,
            y: currentFrame.midY - targetFrame.height / 2,
            width: targetFrame.width,
            height: targetFrame.height
        )
    }

    private func topCenteredFrame(
        forContentSize contentSize: NSSize,
        around currentFrame: NSRect,
        in panel: NSPanel
    ) -> NSRect {
        let targetFrame = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        )
        return NSRect(
            x: currentFrame.midX - targetFrame.width / 2,
            y: currentFrame.maxY - targetFrame.height,
            width: targetFrame.width,
            height: targetFrame.height
        )
    }

    private func minimizedContentWidth() -> CGFloat {
        PanelLayoutMetrics.minimizedWindowWidth(forTitle: noteStore.currentNote?.title ?? "")
    }

    private func restoredFullSizeFrame(around currentFrame: NSRect, in panel: NSPanel) -> NSRect {
        if let lastFullSizeFrame {
            let restoredContentSize = panel.contentRect(forFrameRect: lastFullSizeFrame).size
            return topCenteredFrame(
                forContentSize: restoredContentSize,
                around: currentFrame,
                in: panel
            )
        }

        return topCenteredFrame(
            forContentSize: NSSize(
                width: PanelLayoutMetrics.minimumWindowWidth,
                height: currentHeight
            ),
            around: currentFrame,
            in: panel
        )
    }

    private func recordCurrentFullSizeFrame() {
        guard let p = panel, !panelPresentation.isMinimized, overlayOverrideHeight == 0 else { return }
        lastFullSizeFrame = p.frame
    }

    private func animatePanel(
        to frame: NSRect,
        duration: TimeInterval,
        timingName: CAMediaTimingFunctionName
    ) {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: timingName)
            p.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - App Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(settingsStore.value.showInDock ? .regular : .accessory)
        setupPanel()
        installOutsideClickMonitor()
        applyTheme(settingsStore.value.theme)
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
        removeOutsideClickMonitor()
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        let isFirstRun = !settingsStore.value.onboarded
        let initialHeight = isFirstRun ? onboardingHeight : compactHeight

        let contentView = ContentView(
            noteStore: noteStore,
            panelPresentation: panelPresentation,
            settings: settingsBinding(),
            onHeightChange: { [weak self] h in
                self?.animateHeight(h, allowShrink: false)
            },
            onNoteSwitchHeight: { [weak self] h in
                self?.animateNoteSwitchHeight(h)
            },
            onOnboardingComplete: { [weak self] in
                self?.animateOnboardingDismiss()
            },
            onOverrideHeight: { [weak self] height in
                self?.applyOverrideHeight(height)
            },
            onMinimizedWidthChange: { [weak self] width in
                self?.updateMinimizedWidth(width)
            },
            onClose: { [weak self] in self?.hidePanel() },
            onMinimize: { [weak self] in self?.enterMinimizedMode() },
            onExpand: { [weak self] in self?.toggleExpand() },
            onRestoreFromMinimized: { [weak self] in self?.exitMinimizedMode() }
        )

        let initialWidth = isFirstRun ? onboardingWidth : PanelLayoutMetrics.minimumWindowWidth
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
        // Only become key when a clicked view explicitly needs keyboard focus.
        // This makes text inputs inside Buoy focusable while reducing accidental
        // key capture when the user is interacting with another app's dialogs.
        p.becomesKeyOnlyIfNeeded = true
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.minSize = NSSize(
            width: PanelLayoutMetrics.minimizedWindowMinimumWidth,
            height: PanelLayoutMetrics.minimizedWindowHeight
        )
        p.delegate = self
        p.contentView = hosting

        panel = p
        hostingView = hosting
        currentHeight = initialHeight
        panelPresentation.minimizedContentWidth = minimizedContentWidth()
    }

    private func animateOnboardingDismiss() {
        guard let p = panel else { return }
        let targetWidth = PanelLayoutMetrics.minimumWindowWidth
        let targetHeight = compactHeight
        let currentFrame = p.frame
        let newFrame = centeredFrame(
            forContentSize: NSSize(width: targetWidth, height: targetHeight),
            around: currentFrame,
            in: p
        )
        currentHeight = targetHeight
        panelPresentation.fullSizeMode = .compact
        lastFullSizeFrame = newFrame
        animatePanel(to: newFrame, duration: 0.55, timingName: .easeInEaseOut)
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
        let settingsItem = menu.addItem(withTitle: "Settings", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
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
            if !panelPresentation.isMinimized {
                lastFullSizeFrame = p.frame
            }
        }
        p.allowsKeyFocus = true
        p.makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        panel?.orderOut(nil)
    }

    private func installOutsideClickMonitor() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleMonitoredMouseDown(screenPoint: event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.handleMonitoredMouseDown(screenPoint: NSEvent.mouseLocation)
        }
    }

    private func removeOutsideClickMonitor() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func handleMonitoredMouseDown(screenPoint: NSPoint) {
        if Thread.isMainThread {
            handleOutsideMouseDownOnMainThread(screenPoint: screenPoint)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.handleOutsideMouseDownOnMainThread(screenPoint: screenPoint)
            }
        }
    }

    private func handleOutsideMouseDownOnMainThread(screenPoint: NSPoint) {
        guard let p = panel, p.isVisible else { return }
        guard !p.frame.contains(screenPoint) else { return }

        p.allowsKeyFocus = false
        p.endEditing(for: nil)
        p.makeFirstResponder(nil)

        if p.isKeyWindow {
            p.resignKey()
        }

        if p.isMainWindow {
            p.resignMain()
        }
    }

    func toggleExpand() {
        guard !panelPresentation.isMinimized else { return }
        panelPresentation.fullSizeMode =
            panelPresentation.fullSizeMode == .expanded ? .compact : .expanded
        let targetHeight = panelPresentation.fullSizeMode == .expanded ? expandedHeight : compactHeight
        animateHeight(targetHeight, allowShrink: true)
    }

    @objc func toggleMinimizedMode(_ sender: Any?) {
        guard let p = panel, p.isVisible else { return }
        if panelPresentation.isMinimized {
            exitMinimizedMode()
        } else {
            enterMinimizedMode()
        }
    }

    @objc private func minimizePanel(_ sender: Any?) {
        guard let p = panel, p.isVisible else { return }
        guard !panelPresentation.isMinimized else { return }
        enterMinimizedMode()
    }

    private func enterMinimizedMode() {
        guard let p = panel, !panelPresentation.isMinimized else { return }

        // Only capture the full-size frame when no minimize transition is in flight.
        // If a restore animation is mid-way, p.frame is an intermediate value and
        // would corrupt lastFullSizeFrame, causing the panel to restore as a square.
        if overlayOverrideHeight == 0 && !isMinimizeAnimating {
            lastFullSizeFrame = p.frame
        }

        panelPresentation.minimizedContentWidth = minimizedContentWidth()
        let targetFrame = topCenteredFrame(
            forContentSize: NSSize(
                width: panelPresentation.minimizedContentWidth,
                height: PanelLayoutMetrics.minimizedWindowHeight
            ),
            around: p.frame,
            in: p
        )

        withAnimation(.easeInOut(duration: PanelLayoutMetrics.minimizedTransitionDuration)) {
            panelPresentation.isMinimized = true
        }
        refreshMinimizeMenuItem()
        isMinimizeAnimating = true
        animatePanel(
            to: targetFrame,
            duration: PanelLayoutMetrics.minimizedFrameAnimationDuration,
            timingName: .easeInEaseOut
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + PanelLayoutMetrics.minimizedFrameAnimationDuration + 0.05
        ) { [weak self] in
            self?.isMinimizeAnimating = false
        }
    }

    private func exitMinimizedMode() {
        guard panelPresentation.isMinimized else { return }
        guard let p = panel else { return }

        let targetFrame = restoredFullSizeFrame(around: p.frame, in: p)

        withAnimation(.easeInOut(duration: PanelLayoutMetrics.minimizedTransitionDuration)) {
            panelPresentation.isMinimized = false
        }
        refreshMinimizeMenuItem()
        isMinimizeAnimating = true
        animatePanel(
            to: targetFrame,
            duration: PanelLayoutMetrics.minimizedFrameAnimationDuration,
            timingName: .easeInEaseOut
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + PanelLayoutMetrics.minimizedFrameAnimationDuration + 0.05
        ) { [weak self] in
            self?.isMinimizeAnimating = false
        }
    }

    private func updateMinimizedWidth(_ width: CGFloat) {
        panelPresentation.minimizedContentWidth = width
        guard panelPresentation.isMinimized, let p = panel else { return }

        let targetFrame = topCenteredFrame(
            forContentSize: NSSize(
                width: width,
                height: PanelLayoutMetrics.minimizedWindowHeight
            ),
            around: p.frame,
            in: p
        )
        animatePanel(to: targetFrame, duration: 0.18, timingName: .easeInEaseOut)
    }

    func animateHeight(
        _ newHeight: CGFloat,
        allowShrink: Bool,
        duration: TimeInterval = 0.15,
        timingName: CAMediaTimingFunctionName = .easeOut
    ) {
        guard let p = panel else { return }
        guard !panelPresentation.isMinimized else { return }
        let liveHeight = panelContentHeight(p)
        if overlayOverrideHeight == 0 {
            currentHeight = max(PanelLayoutMetrics.minimumWindowHeight, liveHeight)
        }
        let target = max(PanelLayoutMetrics.minimumWindowHeight, min(PanelLayoutMetrics.maximumAutoHeight, newHeight))
        guard allowShrink || target > liveHeight else { return }
        currentHeight = target
        let effectiveTarget = max(target, overlayOverrideHeight)
        guard abs(liveHeight - effectiveTarget) > 0.5 else { return }
        let currentFrame = p.frame
        let currentContentWidth = panelContentSize(p).width
        let targetFrame = frame(
            forContentSize: NSSize(width: currentContentWidth, height: effectiveTarget),
            preservingTopOf: currentFrame,
            in: p
        )
        animatePanel(to: targetFrame, duration: duration, timingName: timingName)
        if overlayOverrideHeight == 0 {
            lastFullSizeFrame = targetFrame
        }
    }

    private func animateNoteSwitchHeight(_ newHeight: CGFloat) {
        guard let p = panel else { return }
        guard !panelPresentation.isMinimized else { return }
        let liveHeight = panelContentHeight(p)
        if overlayOverrideHeight == 0 {
            currentHeight = max(PanelLayoutMetrics.minimumWindowHeight, liveHeight)
        }

        let target = max(
            PanelLayoutMetrics.minimumWindowHeight,
            min(PanelLayoutMetrics.maximumAutoHeight, newHeight)
        )
        currentHeight = target

        let effectiveTarget = max(target, overlayOverrideHeight)
        guard abs(liveHeight - effectiveTarget) > 0.5 else { return }

        let targetFrame = frame(
            forContentSize: NSSize(width: panelContentSize(p).width, height: effectiveTarget),
            preservingTopOf: p.frame,
            in: p
        )
        animatePanel(to: targetFrame, duration: 0.28, timingName: .easeInEaseOut)
        if overlayOverrideHeight == 0 {
            lastFullSizeFrame = targetFrame
        }
    }

    func applyOverrideHeight(_ height: CGFloat?) {
        guard let p = panel else { return }
        let liveHeight = panelContentHeight(p)
        if overlayOverrideHeight == 0, height != nil, !panelPresentation.isMinimized {
            // When opening an overlay, honor the live panel height so a larger window
            // doesn't get snapped down to the fixed overlay override.
            currentHeight = max(PanelLayoutMetrics.minimumWindowHeight, liveHeight)
        }
        overlayOverrideHeight = height ?? 0
        guard !panelPresentation.isMinimized else { return }
        let target = max(currentHeight, overlayOverrideHeight)
        let clampedTarget = max(PanelLayoutMetrics.minimumWindowHeight, target)
        guard abs(liveHeight - clampedTarget) > 0.5 else { return }
        let targetFrame = frame(
            forContentSize: NSSize(width: panelContentSize(p).width, height: clampedTarget),
            preservingTopOf: p.frame,
            in: p
        )
        animatePanel(to: targetFrame, duration: 0.25, timingName: .easeInEaseOut)
        if overlayOverrideHeight == 0 {
            lastFullSizeFrame = targetFrame
        }
    }

    // MARK: - Menu Actions

    @objc private func openSettings() {
        showPanel()
        if panelPresentation.isMinimized {
            exitMinimizedMode()
        }
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    @objc private func handleSettingsUpdate() {
        applyTheme(settingsStore.value.theme)
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
        let minimizeItem = windowMenu.addItem(withTitle: "Minimize", action: #selector(toggleMinimizedMode(_:)), keyEquivalent: "m")
        minimizeItem.target = self
        minimizeRestoreMenuItem = minimizeItem
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
        refreshMinimizeMenuItem()
    }

    private func refreshMinimizeMenuItem() {
        minimizeRestoreMenuItem?.title = panelPresentation.isMinimized ? "Restore" : "Minimize"
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // On macOS 15, NSHostingView doesn't automatically route keyboard events
        // to embedded NSViewRepresentable text views. Post a notification so
        // ContentView can focus the editor if nothing else is already focused.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .buoyPanelBecameKey, object: nil)
        }
    }

    func windowDidMove(_ notification: Notification) {
        recordCurrentFullSizeFrame()
    }

    func windowDidResize(_ notification: Notification) {
        recordCurrentFullSizeFrame()
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
