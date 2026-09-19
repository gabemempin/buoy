import AppKit
import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: BuoyPanel?
    private var statusItem: NSStatusItem?
    var minimizeRestoreMenuItem: NSMenuItem?
    /// Retained so the Edit menu keeps a live delegate for its Undo/Redo titles.
    let editMenuDelegate = EditMenuDelegate()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private let cornerResizeOverlayController = CornerResizeOverlayController()
    /// The last settings values whose side effects were applied. `.settingsDidChange`
    /// fires for every field, but activation policy, the login item and the global
    /// hotkey must only be touched when their own value actually moved.
    private var appliedSettings = AppSettings()

    let noteStore = NoteStore()
    var settingsStore = SettingsStore()
    let panelPresentation = PanelPresentationModel()

    /// The panel's default height: the shortest it can be while still drawing
    /// regular chrome. Distinct from `PanelLayoutMetrics.minimumWindowHeight`,
    /// which is the compact chrome's floor and is what the user can drag to.
    private let compactHeight: CGFloat = PanelLayoutMetrics.regularChromeWindowHeight
    private let onboardingWidth: CGFloat = 360
    private let onboardingHeight: CGFloat = 520
    private let expandedHeight: CGFloat = 780
    private var currentHeight: CGFloat = PanelLayoutMetrics.regularChromeWindowHeight
    private var overlayOverrideHeight: CGFloat = 0
    private var hasPositioned = false
    private var lastFullSizeFrame: NSRect?
    private var isMinimizeAnimating = false
    private var minimizeAnimationGeneration = 0

    private func panelContentHeight(_ panel: NSPanel) -> CGFloat {
        panel.contentRect(forFrameRect: panel.frame).height
    }

    private func panelContentSize(_ panel: NSPanel) -> NSSize {
        panel.contentRect(forFrameRect: panel.frame).size
    }

    private var normalPanelMinimumSize: NSSize {
        NSSize(
            width: PanelLayoutMetrics.minimumWindowWidth,
            height: PanelLayoutMetrics.minimumWindowHeight
        )
    }

    private var minimizedPanelMinimumSize: NSSize {
        NSSize(
            width: PanelLayoutMetrics.minimizedWindowMinimumWidth,
            height: PanelLayoutMetrics.minimizedWindowHeight
        )
    }

    private func applyPanelMinimumSize(forMinimizedLayout isMinimizedLayout: Bool? = nil) {
        guard let p = panel else { return }
        let usesMinimizedLayout = isMinimizedLayout ?? (panelPresentation.isMinimized || isMinimizeAnimating)
        p.minSize = usesMinimizedLayout ? minimizedPanelMinimumSize : normalPanelMinimumSize
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

    private func frame(
        forContentSize contentSize: NSSize,
        preservingBottomOf currentFrame: NSRect,
        in panel: NSPanel
    ) -> NSRect {
        var f = panel.frameRect(forContentRect: NSRect(origin: currentFrame.origin, size: contentSize))
        f.origin.x = currentFrame.origin.x
        f.origin.y = currentFrame.origin.y
        return f
    }

    private func bottomCenteredFrame(
        forContentSize contentSize: NSSize,
        around currentFrame: NSRect,
        in panel: NSPanel
    ) -> NSRect {
        let targetFrame = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        )
        return NSRect(
            x: currentFrame.midX - targetFrame.width / 2,
            y: currentFrame.minY,
            width: targetFrame.width,
            height: targetFrame.height
        )
    }

    private func clampedToVisibleFrame(_ frame: NSRect, in panel: NSPanel) -> NSRect {
        let screen = panel.screen
            ?? NSScreen.screens.first { $0.frame.intersects(frame) }
            ?? NSScreen.main
        // Clamp the glass to the screen, letting the transparent shadow margin
        // overhang the edge (the window frame is glassEdgeInset larger per side).
        guard let visible = screen?.visibleFrame.insetBy(
            dx: -PanelLayoutMetrics.glassEdgeInset,
            dy: -PanelLayoutMetrics.glassEdgeInset
        ) else { return frame }
        var f = frame
        f.size.width  = min(f.size.width,  visible.width)
        f.size.height = min(f.size.height, visible.height)
        if f.maxX > visible.maxX { f.origin.x = visible.maxX - f.width }
        if f.minX < visible.minX { f.origin.x = visible.minX }
        if f.maxY > visible.maxY { f.origin.y = visible.maxY - f.height }
        if f.minY < visible.minY { f.origin.y = visible.minY }
        return f
    }

    /// Returns a frame for `contentSize` grown from `currentFrame`, choosing an anchor
    /// that keeps the result on-screen. Prefers top-anchored (downward growth); switches
    /// to bottom-anchored (upward growth) if the bottom would clip below the visible area.
    /// Always applies `clampedToVisibleFrame` as a final safety net.
    private func resizedFrame(
        contentSize: NSSize,
        currentFrame: NSRect,
        in panel: NSPanel,
        centerHorizontally: Bool
    ) -> NSRect {
        let topAnchored = centerHorizontally
            ? topCenteredFrame(forContentSize: contentSize, around: currentFrame, in: panel)
            : frame(forContentSize: contentSize, preservingTopOf: currentFrame, in: panel)
        let visibleMinY = (panel.screen ?? NSScreen.main)?.visibleFrame.minY
        let needsBottomAnchor = visibleMinY.map { topAnchored.minY < $0 } ?? false
        let chosen = needsBottomAnchor
            ? (centerHorizontally
                ? bottomCenteredFrame(forContentSize: contentSize, around: currentFrame, in: panel)
                : frame(forContentSize: contentSize, preservingBottomOf: currentFrame, in: panel))
            : topAnchored
        return clampedToVisibleFrame(chosen, in: panel)
    }

    private func minimizedContentWidth() -> CGFloat {
        PanelLayoutMetrics.minimizedWindowWidth(forTitle: noteStore.currentNote?.title ?? "")
    }

    private func shouldUseBottomMinimizedAnchor(for frame: NSRect, in panel: NSPanel) -> Bool {
        guard let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame else { return false }
        let lowerBandMaxY = visibleFrame.minY + visibleFrame.height * 0.35
        return frame.midY < lowerBandMaxY
    }

    private func restoredFullSizeFrame(around currentFrame: NSRect, in panel: NSPanel) -> NSRect {
        let contentSize = lastFullSizeFrame
            .flatMap { restorableFullContentSize(fromFrame: $0, in: panel) }
            ?? NSSize(width: PanelLayoutMetrics.regularChromeWindowWidth, height: currentHeight)
        return resizedFrame(contentSize: contentSize, currentFrame: currentFrame, in: panel, centerHorizontally: true)
    }

    private func recordCurrentFullSizeFrame() {
        guard let p = panel,
              !panelPresentation.isMinimized,
              !isMinimizeAnimating,
              overlayOverrideHeight == 0,
              restorableFullContentSize(fromFrame: p.frame, in: p) != nil
        else { return }
        lastFullSizeFrame = p.frame
    }

    private func restorableFullContentSize(fromFrame frame: NSRect, in panel: NSPanel) -> NSSize? {
        let contentSize = panel.contentRect(forFrameRect: frame).size
        guard contentSize.width >= PanelLayoutMetrics.minimumWindowWidth - 0.5,
              contentSize.height >= PanelLayoutMetrics.minimumWindowHeight - 0.5
        else { return nil }
        return contentSize
    }

    private func beginMinimizeAnimation() -> Int {
        minimizeAnimationGeneration += 1
        isMinimizeAnimating = true
        return minimizeAnimationGeneration
    }

    private func finishMinimizeAnimation(generation: Int, restoredFrame: NSRect? = nil) {
        guard minimizeAnimationGeneration == generation else { return }
        isMinimizeAnimating = false
        if let restoredFrame, overlayOverrideHeight == 0, !panelPresentation.isMinimized {
            lastFullSizeFrame = restoredFrame
        }
    }

    private func animatePanel(
        to frame: NSRect,
        duration: TimeInterval,
        timingName: CAMediaTimingFunctionName,
        completion: (() -> Void)? = nil
    ) {
        guard let p = panel else {
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            // Single choke point for every panel frame animation — Harbor Mode,
            // auto-height, overlay height overrides and pill width all land
            // here — so Reduce Motion only needs gating once. At duration 0 the
            // frame is set outright and the completion handler still runs, which
            // the minimize generation guards depend on.
            ctx.duration = BuoyMotion.duration(duration)
            ctx.timingFunction = CAMediaTimingFunction(name: timingName)
            p.animator().setFrame(frame, display: true)
        }, completionHandler: {
            completion?()
        })
    }

    // MARK: - App Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        let showInDock = settingsStore.value.showInDock
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
            if showInDock { NSApp.activate(ignoringOtherApps: true) }
        }
        appliedSettings = settingsStore.value
        BuoyTheme.setCurrent(BuoyTheme(settings: settingsStore.value))
        ShortcutRegistry.update(from: settingsStore.value)
        noteStore.restoreSelection(noteID: settingsStore.value.lastSelectedNoteID)
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
        settingsStore.flush()
        removeOutsideClickMonitor()
        cornerResizeOverlayController.detach()
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        let isFirstRun = !settingsStore.value.onboarded
        // The What's New splash needs the same tall panel Settings uses. Size the
        // window for it up front so it doesn't visibly stretch a beat after launch.
        let showsWhatsNew = !isFirstRun
            && WhatsNewCatalog.shouldPresent(settings: settingsStore.value)
        let initialHeight: CGFloat
        if isFirstRun {
            initialHeight = onboardingHeight
        } else if showsWhatsNew {
            initialHeight = PanelLayoutMetrics.whatsNewOverrideHeight
        } else {
            initialHeight = compactHeight
        }

        let contentView = ContentView(
            noteStore: noteStore,
            panelPresentation: panelPresentation,
            settings: settingsBinding(),
            onOnboardingComplete: { [weak self] in
                self?.animateOnboardingDismiss()
            },
            onOverrideHeight: { [weak self] height in
                self?.applyOverrideHeight(height)
            },
            onMinimizedWidthChange: { [weak self] width in
                self?.updateMinimizedWidth(width)
            },
            onCornerResizeAvailabilityChange: { [weak self] isAvailable in
                self?.cornerResizeOverlayController.setEnabled(isAvailable)
            },
            onClose: { [weak self] in self?.hidePanel() },
            onMinimize: { [weak self] in self?.enterMinimizedMode() },
            onExpand: { [weak self] in self?.toggleExpand() },
            onRestoreFromMinimized: { [weak self] in self?.exitMinimizedMode() }
        )

        let initialWidth = isFirstRun ? onboardingWidth : PanelLayoutMetrics.regularChromeWindowWidth
        let initialRect = NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight)

        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = initialRect
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        // Prevent SwiftUI from pushing min/max content-size constraints up to the
        // NSPanel. We manage the panel's frame and minSize directly via animatePanel,
        // and SwiftUI's push collides with AppKit's constraint cycle during the
        // Harbor Mode frame animation — re-entering Harbor Mode after a restore
        // crashes in -[NSWindow _postWindowNeedsUpdateConstraints].
        hosting.sizingOptions = []

        let p = BuoyPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = settingsStore.value.alwaysOnTop ? .statusBar : .normal
        p.isOpaque = false
        p.backgroundColor = .clear
        // No AppKit window shadow. A window shadow's inner portion is normally
        // hidden behind opaque window content — but this panel is transparent,
        // so that inner edge is never covered and renders as a hard dark ring:
        // on the glass edge when the surface filled the window (the original
        // "black stroke"), and floating at the window bounds once glassEdgeInset
        // pulled the surface inward. Inactive windows render it stronger still.
        // Liquid Glass carries its own depth, so let the material supply it.
        //
        // If a heavier drop shadow is ever wanted, do NOT use a plain SwiftUI
        // .shadow() here: it draws behind the surface and shows straight through
        // the translucent glass as a dark pool. It has to be masked into a ring
        // with the surface's own shape punched out.
        p.hasShadow = false
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        // Only become key when a clicked view explicitly needs keyboard focus.
        // This makes text inputs inside Buoy focusable while reducing accidental
        // key capture when the user is interacting with another app's dialogs.
        p.becomesKeyOnlyIfNeeded = true
        // The link editor and other transient panels add and remove controls at
        // runtime. Let AppKit rebuild the Tab/Shift-Tab order with the hierarchy.
        p.autorecalculatesKeyViewLoop = true
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self
        p.contentView = hosting

        panel = p
        cornerResizeOverlayController.attach(to: p)
        applyPanelMinimumSize(forMinimizedLayout: false)
        // `currentHeight` is the height to fall back to once an overlay closes, so
        // it must stay compact even though the window opens tall. Declaring the
        // override here also makes ContentView's first `onOverrideHeight` a no-op
        // (live height already equals the target) instead of an absorbed resize.
        currentHeight = showsWhatsNew ? compactHeight : initialHeight
        if showsWhatsNew {
            overlayOverrideHeight = PanelLayoutMetrics.whatsNewOverrideHeight
        }
        panelPresentation.minimizedContentWidth = minimizedContentWidth()
    }

    private func animateOnboardingDismiss() {
        guard let p = panel else { return }
        let targetWidth = PanelLayoutMetrics.regularChromeWindowWidth
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
        // The menu bar item is the app's only permanent affordance, and a bare
        // image reaches VoiceOver as an unnamed button without this.
        button.setAccessibilityLabel("Buoy")
        button.setAccessibilityHelp("Show or hide the Buoy note panel")
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    /// Right-click menu on the menu bar icon.
    ///
    /// With "Show in Dock" off, Buoy is an `.accessory` app and therefore has no
    /// menu bar at all — `NSApp.mainMenu` exists but is never displayed. This is
    /// the only always-available menu, so it carries the app-level commands
    /// rather than just Settings and Quit.
    private func showContextMenu() {
        let menu = NSMenu()

        let newNote = menu.addItem(withTitle: "New Note", action: #selector(newNoteFromMenu), keyEquivalent: "")
        newNote.target = self
        if let equivalent = ShortcutRegistry.combo(for: .newNote).menuKeyEquivalent {
            newNote.keyEquivalent = equivalent.key
            newNote.keyEquivalentModifierMask = equivalent.modifiers
        }

        menu.addItem(.separator())

        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        if let equivalent = ShortcutRegistry.combo(for: .openSettings).menuKeyEquivalent {
            settingsItem.keyEquivalent = equivalent.key
            settingsItem.keyEquivalentModifierMask = equivalent.modifiers
        }

        menu.addItem(
            withTitle: "About Buoy",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Buoy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func newNoteFromMenu() {
        showPanel()
        if panelPresentation.isMinimized { exitMinimizedMode() }
        NotificationCenter.default.post(name: .buoyNewNote, object: nil)
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
            // Never record an overlay-inflated frame as the restore target
            // (same rule as `recordCurrentFullSizeFrame`).
            if !panelPresentation.isMinimized, overlayOverrideHeight == 0 {
                lastFullSizeFrame = p.frame
            }
        }
        p.allowsKeyFocus = true
        p.setFrame(clampedToVisibleFrame(p.frame, in: p), display: false)
        cornerResizeOverlayController.updateFrames()
        p.makeKeyAndOrderFront(nil)
        cornerResizeOverlayController.parentDidShow()
    }

    @objc func hidePanel(_ sender: Any? = nil) {
        cornerResizeOverlayController.parentWillHide()
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

    /// Whether a click landed in something the panel put on screen rather than
    /// somewhere else entirely.
    ///
    /// Popovers — Settings, the link editor, Transfer to Apple Notes — are
    /// their own windows, and every one of them sits outside the panel's frame
    /// by definition. Treating that as an outside click made the panel resign
    /// key on the way down, which closed the popover before the control under
    /// the pointer ever saw the event: the Settings popover could be opened but
    /// nothing inside it could be clicked.
    private func isInsideAttachedWindow(_ screenPoint: NSPoint) -> Bool {
        NSApp.windows.contains { window in
            guard window !== panel, window.isVisible else { return false }
            return window.frame.contains(screenPoint)
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
        guard !p.frame.contains(screenPoint),
              !cornerResizeOverlayController.containsInteractiveControl(at: screenPoint),
              !isInsideAttachedWindow(screenPoint)
        else { return }

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

    private func enterMinimizedMode() {
        guard let p = panel, !panelPresentation.isMinimized else { return }
        let wasMinimizeAnimating = isMinimizeAnimating
        let generation = beginMinimizeAnimation()
        applyPanelMinimumSize(forMinimizedLayout: true)

        // Only capture the full-size frame when no minimize transition is in flight.
        // If a restore animation is mid-way, p.frame is an intermediate value and
        // would corrupt lastFullSizeFrame, causing the panel to restore as a square.
        if overlayOverrideHeight == 0,
           !wasMinimizeAnimating,
           restorableFullContentSize(fromFrame: p.frame, in: p) != nil {
            lastFullSizeFrame = p.frame
        }
        p.endEditing(for: nil)
        p.makeFirstResponder(nil)

        panelPresentation.minimizedContentWidth = minimizedContentWidth()
        let pillSize = NSSize(
            width: panelPresentation.minimizedContentWidth,
            height: PanelLayoutMetrics.minimizedWindowHeight
        )
        let anchoredFrame = shouldUseBottomMinimizedAnchor(for: p.frame, in: p)
            ? bottomCenteredFrame(forContentSize: pillSize, around: p.frame, in: p)
            : topCenteredFrame(forContentSize: pillSize, around: p.frame, in: p)
        let targetFrame = clampedToVisibleFrame(anchoredFrame, in: p)

        withAnimation(BuoyMotion.easeInOut(PanelLayoutMetrics.minimizedTransitionDuration)) {
            panelPresentation.isMinimized = true
        }
        refreshMinimizeMenuItem()
        animatePanel(
            to: targetFrame,
            duration: PanelLayoutMetrics.minimizedFrameAnimationDuration,
            timingName: .easeInEaseOut
        ) { [weak self] in
            self?.finishMinimizeAnimation(generation: generation)
        }
    }

    private func exitMinimizedMode() {
        guard panelPresentation.isMinimized else { return }
        guard let p = panel else { return }
        let generation = beginMinimizeAnimation()

        let targetFrame = restoredFullSizeFrame(around: p.frame, in: p)

        withAnimation(BuoyMotion.easeInOut(PanelLayoutMetrics.minimizedTransitionDuration)) {
            panelPresentation.isMinimized = false
        }
        refreshMinimizeMenuItem()
        // Defer the window-frame animation to the next runloop iteration so the
        // SwiftUI content swap (pill → full editor) completes its layout pass
        // before AppKit runs setFrame(display: true). Running both in the same
        // iteration re-enters the window's constraint update and crashes in
        // -[NSWindow _postWindowNeedsUpdateConstraints] when restoring from
        // Harbor Mode (the full editor remounts NSTextView mid-resize).
        DispatchQueue.main.async { [weak self] in
            guard let self, self.minimizeAnimationGeneration == generation else { return }
            self.animatePanel(
                to: targetFrame,
                duration: PanelLayoutMetrics.minimizedFrameAnimationDuration,
                timingName: .easeInEaseOut
            ) { [weak self] in
                guard let self, self.minimizeAnimationGeneration == generation else { return }
                self.finishMinimizeAnimation(generation: generation, restoredFrame: targetFrame)
                self.applyPanelMinimumSize(forMinimizedLayout: false)
            }
        }
    }

    private func updateMinimizedWidth(_ width: CGFloat) {
        panelPresentation.minimizedContentWidth = width
        guard panelPresentation.isMinimized, let p = panel else { return }

        let pillSize = NSSize(width: width, height: PanelLayoutMetrics.minimizedWindowHeight)
        let anchoredFrame = shouldUseBottomMinimizedAnchor(for: p.frame, in: p)
            ? bottomCenteredFrame(forContentSize: pillSize, around: p.frame, in: p)
            : topCenteredFrame(forContentSize: pillSize, around: p.frame, in: p)
        let targetFrame = clampedToVisibleFrame(anchoredFrame, in: p)
        animatePanel(to: targetFrame, duration: 0.18, timingName: .easeInEaseOut)
    }

    func animateHeight(
        _ newHeight: CGFloat,
        allowShrink: Bool,
        duration: TimeInterval = 0.15,
        timingName: CAMediaTimingFunctionName = .easeOut
    ) {
        guard let p = panel else { return }
        guard !panelPresentation.isMinimized, !isMinimizeAnimating else { return }
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
        let targetFrame = resizedFrame(
            contentSize: NSSize(width: currentContentWidth, height: effectiveTarget),
            currentFrame: currentFrame,
            in: p,
            centerHorizontally: false
        )
        animatePanel(to: targetFrame, duration: duration, timingName: timingName)
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
        applyPanelMinimumSize()
        guard !panelPresentation.isMinimized else { return }
        let target = max(currentHeight, overlayOverrideHeight)
        let clampedTarget = max(PanelLayoutMetrics.minimumWindowHeight, target)
        guard abs(liveHeight - clampedTarget) > 0.5 else { return }
        let targetFrame = resizedFrame(
            contentSize: NSSize(width: panelContentSize(p).width, height: clampedTarget),
            currentFrame: p.frame,
            in: p,
            centerHorizontally: false
        )
        animatePanel(to: targetFrame, duration: 0.25, timingName: .easeInEaseOut)
        if overlayOverrideHeight == 0 {
            lastFullSizeFrame = targetFrame
        }
    }

    // MARK: - Menu Actions

    /// Opens the Settings window. Deliberately does *not* show or restore the
    /// note panel: Settings is its own window now, and yanking the panel out of
    /// Harbor Mode to open a window somewhere else would be a non sequitur.
    /// Asks the panel to show its Settings popover.
    ///
    /// Settings is anchored to the footer's gear rather than being a window of
    /// its own, so opening it means bringing the panel forward and telling it
    /// to toggle — there is nothing here to order front.
    @objc func openSettings() {
        showPanel()
        if panelPresentation.isMinimized { exitMinimizedMode() }
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    /// Creates the ephemeral bug-report note. Called from the About page, which
    /// lives in another window, so the panel has to be brought back first.
    private func startBugReport() {
        showPanel()
        if panelPresentation.isMinimized { exitMinimizedMode() }
        NotificationCenter.default.post(name: .buoyStartBugReport, object: nil)
    }

    @objc private func handleSettingsUpdate() {
        let settings = settingsStore.value
        defer { appliedSettings = settings }

        // Published before anything renders, because the AppKit side of the
        // app (the editor's selection colour, the to-do checkboxes, the corner
        // arcs) reads the theme from this static rather than the environment.
        BuoyTheme.setCurrent(BuoyTheme(settings: settings))
        applyTheme(settings.theme)

        if settings.shortcuts != appliedSettings.shortcuts {
            ShortcutRegistry.update(from: settings)
            // The menu bar holds its key equivalents as literal characters, so
            // a rebind has to rewrite the items rather than being looked up.
            buildMainMenu()
        }
        panel?.level = settings.alwaysOnTop ? .statusBar : .normal
        cornerResizeOverlayController.syncWindowProperties()


        // The three below used to be applied inline by the settings overlay's
        // own `onChange` handlers. They belong here now that the view is in a
        // separate window, and each is guarded because this runs for every
        // settings write, not just its own.
        if settings.showInDock != appliedSettings.showInDock {
            NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
            if settings.showInDock { NSApp.activate(ignoringOtherApps: true) }
        }
        if settings.launchAtLogin != appliedSettings.launchAtLogin {
            LaunchAtLogin.isEnabled = settings.launchAtLogin
        }
        if settings.globalShortcut != appliedSettings.globalShortcut {
            HotkeyService.shared.register(shortcut: settings.globalShortcut)
        }
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

    func refreshMinimizeMenuItem() {
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
        cornerResizeOverlayController.updateFrames()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Enforce the floor against the metric constants directly rather than
        // `sender.minSize`: because the hosting view uses `sizingOptions = []`,
        // AppKit's Auto Layout pass recomputes the window's minSize from content
        // (which imposes no minimum) and zeroes out the value we set in
        // applyPanelMinimumSize, so it can't be relied on here.
        let usesMinimizedLayout = panelPresentation.isMinimized || isMinimizeAnimating
        let floor = usesMinimizedLayout ? minimizedPanelMinimumSize : normalPanelMinimumSize
        var constrainedSize = frameSize
        constrainedSize.width = max(constrainedSize.width, floor.width)
        constrainedSize.height = max(constrainedSize.height, floor.height)

        // Hold a detent either side of the compact threshold, so a drag pauses
        // at the boundary and then pops across rather than sliding through it.
        if !usesMinimizedLayout {
            let live = sender.frame.size
            constrainedSize.width = PanelLayoutMetrics.detented(
                proposed: constrainedSize.width,
                current: live.width,
                threshold: PanelLayoutMetrics.compactChromeEnterWidth
            )
            constrainedSize.height = PanelLayoutMetrics.detented(
                proposed: constrainedSize.height,
                current: live.height,
                threshold: PanelLayoutMetrics.compactChromeEnterHeight
            )
        }

        if overlayOverrideHeight > 0 {
            let minWindowHeight = overlayOverrideHeight + sender.frame.height - sender.contentRect(forFrameRect: sender.frame).height
            constrainedSize.height = max(constrainedSize.height, minWindowHeight)
        }

        return constrainedSize
    }

    func windowDidResize(_ notification: Notification) {
        recordCurrentFullSizeFrame()
        cornerResizeOverlayController.updateFrames()
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
    /// Toggles the panel's Settings popover. Posted by ⌘, the menu bar and the
    /// status item, all of which are outside the panel's view tree.
    static let openSettings = Notification.Name("BuoyOpenSettings")

    /// Posted by the Settings popover's About page. The bug-report note lives in
    /// the panel, so the request has to cross windows.
    static let buoyStartBugReport = Notification.Name("BuoyStartBugReport")
}
