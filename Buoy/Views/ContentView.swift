import SwiftUI
import AppKit
import Combine

/// Subscribes to several notifications through a single merged publisher and
/// dispatches by name.
///
/// Purely a compile-time measure: `ContentView.body` is at the type-checker's
/// time budget, so seven separate `.onReceive` modifiers in the chain are enough
/// to tip it into "unable to type-check this expression in reasonable time".
private struct BuoyNotificationRouter: ViewModifier {
    let routes: [Notification.Name: () -> Void]

    func body(content: Content) -> some View {
        content.onReceive(
            Publishers.MergeMany(
                routes.keys.map { NotificationCenter.default.publisher(for: $0) }
            )
        ) { notification in
            routes[notification.name]?()
        }
    }
}

// Class wrapper so the NSTextView reference survives SwiftUI re-renders without triggering update cycles.
private final class TextViewRef {
    var value: BuoyTextView?
}

struct ContentView: View {
    var noteStore: NoteStore
    var panelPresentation: PanelPresentationModel
    @Binding var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    var onOnboardingComplete: (() -> Void)?
    var onOverrideHeight: ((CGFloat?) -> Void)?
    var onMinimizedWidthChange: ((CGFloat) -> Void)?
    var onCornerResizeAvailabilityChange: ((Bool) -> Void)?
    var onClose: () -> Void
    var onMinimize: () -> Void
    var onExpand: () -> Void
    var onRestoreFromMinimized: () -> Void

    // Panel visibility
    @State private var showAllNotes = false
    @State private var showSettings = false
    @State private var showShortcuts = false

    // Bug report mode — tracks the ID of the ephemeral bug report note
    @State private var bugReportNoteID: Note.ID? = nil

    // Link dialog
    @State private var showLinkDialog = false
    @State private var showSelectionLinkDialog = false
    @State private var linkDialogContext = LinkEditingContext.empty
    @State private var selectionLinkPopoverController = SelectionLinkPopoverController()

    // Delete confirmation
    @State private var pendingDeleteNote: Note? = nil
    @State private var pendingDeleteFolder: Folder? = nil

    // All Notes: the folder row currently in inline-rename mode
    @State private var renamingFolderID: String? = nil

    // Toast
    @State private var toastState = ToastState()

    // Text view reference for toolbar actions — @StateObject persists across all re-renders
    @State private var tvRef = TextViewRef()

    // Navigation slide state
    @State private var slideDirection: NavigationDirection? = nil
    @State private var slideID = UUID()

    // Title focus trigger
    @State private var focusTitleTrigger = false

    // Tracks the editor's current selection for the footer word/char count
    @State private var editorSelectedText: String = ""
    @State private var showOnboarding: Bool
    @State private var showMainContent: Bool
    @State private var showWhatsNew: Bool
    /// Holds the splash's panel height through its fade-out, so the window
    /// resizes only after the panel is empty.
    @State private var isDismissingWhatsNew = false

    init(
        noteStore: NoteStore,
        panelPresentation: PanelPresentationModel,
        settings: Binding<AppSettings>,
        onOnboardingComplete: (() -> Void)? = nil,
        onOverrideHeight: ((CGFloat?) -> Void)? = nil,
        onMinimizedWidthChange: ((CGFloat) -> Void)? = nil,
        onCornerResizeAvailabilityChange: ((Bool) -> Void)? = nil,
        onClose: @escaping () -> Void,
        onMinimize: @escaping () -> Void,
        onExpand: @escaping () -> Void,
        onRestoreFromMinimized: @escaping () -> Void
    ) {
        self.noteStore = noteStore
        self.panelPresentation = panelPresentation
        self._settings = settings
        self.onOnboardingComplete = onOnboardingComplete
        self.onOverrideHeight = onOverrideHeight
        self.onMinimizedWidthChange = onMinimizedWidthChange
        self.onCornerResizeAvailabilityChange = onCornerResizeAvailabilityChange
        self.onClose = onClose
        self.onMinimize = onMinimize
        self.onExpand = onExpand
        self.onRestoreFromMinimized = onRestoreFromMinimized
        self._showOnboarding = State(initialValue: !settings.wrappedValue.onboarded)
        self._showMainContent = State(initialValue: settings.wrappedValue.onboarded)
        self._showWhatsNew = State(
            initialValue: WhatsNewCatalog.shouldPresent(settings: settings.wrappedValue)
        )
    }

    var body: some View {
        ZStack {
            if panelPresentation.isMinimized {
                minimizedPanelContent
                    .transition(BuoyMotion.transition(.opacity.combined(with: .scale(scale: 0.96))))
            } else {
                fullPanelContent
                    .transition(BuoyMotion.transition(.scale(scale: 0.7, anchor: .center).combined(with: .opacity)))
            }
        }
        .animation(BuoyMotion.easeInOut(PanelLayoutMetrics.minimizedTransitionDuration), value: panelPresentation.isMinimized)
        // Auto-focus the editor when the panel becomes key (fixes macOS 15 where
        // NSHostingView doesn't automatically route keyboard events to the text view).
        .onReceive(NotificationCenter.default.publisher(for: .buoyPanelBecameKey)) { _ in
            guard !panelPresentation.isMinimized else { return }
            // An opaque splash owns the panel; don't hand focus to the editor
            // hidden behind it.
            guard !showOnboarding, !showWhatsNew else { return }
            let fr = tvRef.value?.window?.firstResponder
            // Only steal focus if nothing meaningful is already focused
            if !(fr is BuoyTextView || fr is NSTextField) {
                focusEditor()
            }
        }
        // App-level commands, posted by BuoyTextView, BuoyPanel and the status
        // item menu. Routed through one merged subscription rather than one
        // `.onReceive` each: ContentView.body sits at the Swift type-checker's
        // time budget and every modifier in the chain counts against it.
        .modifier(BuoyNotificationRouter(routes: [
            .buoyNewNote:         { createNote() },
            .buoyDeleteNote:      { deleteCurrentNote() },
            .buoyCopyToClipboard: { copyToClipboard() },
            .buoyPreviousNote:    { navigateNote(forward: false) },
            .buoyNextNote:        { navigateNote(forward: true) },
            .openShortcuts:       { toggleShortcuts() },
            .openSettings:        { toggleSettings() },
            .buoyAutoTitleFailed: { toastState.show("Couldn't name this note", style: .warning) },
            .buoyAutoTitleUnsupportedLanguage: { toastState.show("Auto-naming isn't available for this note", style: .warning) }
        ]))
        .onReceive(NotificationCenter.default.publisher(for: .showLinkDialog)) { notif in
            guard !panelPresentation.isMinimized else { return }
            guard let context = notif.object as? LinkEditingContext else { return }
            presentLinkDialog(context)
        }
        // Block window dragging whenever any overlay panel is open
        .onChange(of: suppressesEditorCursor) { _, _ in
            let panelOpen = isEditorCoveredByPanel
            NSApp.windows.compactMap { $0 as? NSPanel }.forEach {
                $0.isMovable = !panelOpen
            }
            tvRef.value?.suppressesIBeamCursor = suppressesEditorCursor
        }
        .onChange(of: panelPresentation.isMinimized) { _, isMinimized in
            if isMinimized {
                dismissTransientUI()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + PanelLayoutMetrics.minimizedFrameAnimationDuration) {
                    guard !panelPresentation.isMinimized else { return }
                    guard !showOnboarding, !showWhatsNew else { return }
                    focusEditor()
                }
            }
        }
        .onChange(of: displayTitle) { _, _ in
            onMinimizedWidthChange?(minimizedWidth)
        }
        .onChange(of: noteStore.currentNote?.id) { _, noteID in
            persistCurrentNoteSelection(noteID)
        }
        .onChange(of: activeFooterOverlayHeight) { _, height in
            onOverrideHeight?(height)
        }
        .onChange(of: canUseCornerResizeControls) { _, canUseControls in
            onCornerResizeAvailabilityChange?(canUseControls)
        }
        .onAppear {
            showOnboarding = !settings.onboarded
            persistCurrentNoteSelection(noteStore.currentNote?.id)
            onMinimizedWidthChange?(minimizedWidth)
            onCornerResizeAvailabilityChange?(canUseCornerResizeControls)
            if let height = activeFooterOverlayHeight { onOverrideHeight?(height) }
        }
    }

    private var fullPanelContent: some View {
        fullContent
            .blur(radius: isConfirmingDelete ? 9 : 0)
            .animation(BuoyMotion.easeOut(0.16), value: isConfirmingDelete)
            .padding(PanelLayoutMetrics.windowPadding)
            .frame(
                minWidth: PanelLayoutMetrics.minimumGlassWidth,
                minHeight: PanelLayoutMetrics.minimumGlassHeight
            )
            .background(WindowDragBlocker())
            .overlay { deleteConfirmOverlay }
            .buoyGlass()
    }

    @ViewBuilder
    private var deleteConfirmOverlay: some View {
        if let note = pendingDeleteNote {
            confirmScrim(onDismiss: cancelDeleteNote) {
                DeleteConfirmDialog(
                    noteTitle: note.title,
                    onCancel: { cancelDeleteNote() },
                    onConfirm: { confirmDeleteNote() }
                )
            }
        } else if let folder = pendingDeleteFolder {
            confirmScrim(onDismiss: cancelDeleteFolder) {
                DeleteConfirmDialog(
                    noteTitle: folder.displayName,
                    message: folderDeleteMessage(for: folder),
                    confirmTitle: "Delete Folder",
                    confirmHint: "Deletes the folder. Return does the same.",
                    cancelHint: "Keeps the folder. Escape does the same.",
                    iconName: "folder.badge.minus",
                    onCancel: { cancelDeleteFolder() },
                    onConfirm: { confirmDeleteFolder() }
                )
            }
        }
    }

    private func confirmScrim<Dialog: View>(
        onDismiss: @escaping () -> Void,
        @ViewBuilder dialog: () -> Dialog
    ) -> some View {
        ZStack {
            Color.black.opacity(0.12)
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            dialog()
        }
        // Clip to the window corner radius so the scrim stays concentric with the glass.
        .clipShape(RoundedRectangle(cornerRadius: PanelLayoutMetrics.windowCornerRadius))
        .transition(.opacity)
    }

    private func folderDeleteMessage(for folder: Folder) -> String {
        let count = noteStore.notesInFolder(folder.id).count
        switch count {
        case 0: return "The folder is empty."
        case 1: return "Its note stays in All Notes."
        default: return "Its \(count) notes stay in All Notes."
        }
    }

    private var minimizedPanelContent: some View {
        minimizedContent
            .frame(
                width: panelPresentation.minimizedContentWidth,
                height: PanelLayoutMetrics.minimizedWindowHeight
            )
            .background(WindowDragBlocker())
    }

    private var fullContent: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 4) {
                HeaderView(
                    title: titleBinding,
                    focusTitleTrigger: focusTitleTrigger,
                    onClose: onClose,
                    onMinimize: onMinimize,
                    onExpand: onExpand,
                    onAllNotes: toggleAllNotes,
                    onNewNote: createNote,
                    focusEditor: focusEditor,
                    dragEnabled: !showSettings && !showShortcuts && !showAllNotes && !isLinkDialogPresented,
                    isBugReport: isBugReport,
                    titleReveal: noteStore.titleReveal,
                    onRevealFinished: { noteStore.titleReveal = nil },
                    titleThinking: noteStore.titleThinking != nil && noteStore.titleThinking == noteStore.currentNote?.id
                )

                formattingToolbar

                if let note = noteStore.currentNote {
                    EditorView(
                        rtfData: note.contentRTF,
                        fontSize: settings.fontSize,
                        usesDarkAppearance: usesDarkAppearance,
                        noteID: note.id,
                        placeholder: isBugReport
                            ? "Tell me what you want fixed or improved. If something went wrong, detail how to reproduce the bug.\n\nThank you for making Buoy better!"
                            : "Start typing…",
                        onSelectionChange: { text in
                            editorSelectedText = text
                        },
                        onContentChange: { rtf in
                            noteStore.saveContent(rtf)
                        },
                        textViewRef: { tv in
                            tvRef.value = tv
                            tv.suppressesIBeamCursor = suppressesEditorCursor
                        }
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: PanelLayoutMetrics.editorMinimumHeight,
                        alignment: .leading
                    )
                    .id(slideID)
                    .transition(
                        BuoyMotion.transition(
                            .asymmetric(
                                insertion: .move(edge: slideDirection == .forward ? .trailing : .leading),
                                removal: .move(edge: slideDirection == .forward ? .leading : .trailing)
                            )
                        )
                    )
                }

                FooterView(
                    createdAt: noteStore.currentNote?.createdAt ?? 0,
                    updatedAt: noteStore.currentNote?.updatedAt ?? 0,
                    plainText: noteStore.currentNote.map(NotePlainText.of) ?? "",
                    selectedText: editorSelectedText,
                    onShortcuts: toggleShortcuts,
                    onSettings:  toggleSettings,
                    onTransferToAppleNotes: transferToAppleNotes,
                    onCopy: copyToClipboard,
                    isBugReport: isBugReport,
                    onSendBugReport: sendBugReport,
                    onCancelBugReport: cancelBugReport
                )
                .onChange(of: noteStore.currentNote?.id) { _, _ in
                    editorSelectedText = ""
                }
            }
            .opacity(showMainContent ? 1 : 0)

            ToastContainer(state: toastState)

            if showAllNotes || showSettings || showShortcuts {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(BuoyMotion.easeOut(0.16)) {
                            showAllNotes = false
                            showSettings = false
                            showShortcuts = false
                        }
                        focusEditor()
                    }
            }

            AllNotesOverlay(
                isShowing: $showAllNotes,
                noteStore: noteStore,
                renamingFolderID: $renamingFolderID,
                onDeleteNote: { note in requestDeleteNote(note) },
                onDeleteFolder: { folder in requestDeleteFolder(folder) },
                onFocusEditor: { focusEditor() }
            )

            ZStack(alignment: .bottomLeading) {
                if showSettings {
                    SettingsPanel(
                        isShowing: $showSettings,
                        settings: $settings,
                        onQuit: { NSApp.terminate(nil) },
                        onShortcutChanged: { s in HotkeyService.shared.register(shortcut: s) },
                        onReportBug: { createBugReportNote() }
                    )
                    .padding(.bottom, PanelLayoutMetrics.footerOverlayBottomInset)
                    .padding(.leading, PanelLayoutMetrics.overlayHorizontalInset)
                    .onDisappear { focusEditor() }
                }
                if showShortcuts {
                    ShortcutsPanel(
                        isShowing: $showShortcuts,
                        globalShortcut: electronToSymbols(settings.globalShortcut)
                    )
                    .padding(.bottom, PanelLayoutMetrics.footerOverlayBottomInset)
                    .padding(.leading, PanelLayoutMetrics.overlayHorizontalInset)
                    .onDisappear { focusEditor() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .animation(BuoyMotion.easeOut(0.16), value: showSettings)
            .animation(BuoyMotion.easeOut(0.16), value: showShortcuts)
            .allowsHitTesting(showSettings || showShortcuts)

            UpdateBubbleOverlay(settings: $settings, isSuppressed: !canShowUpdateBubble)

            if showOnboarding {
                OnboardingView(
                    settings: $settings,
                    onShortcutChanged: { s in HotkeyService.shared.register(shortcut: s) },
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 1.0)) {
                            showOnboarding = false
                        }
                        tvRef.value?.suppressesIBeamCursor = isEditorCoveredByPanel
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            onOnboardingComplete?()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
                            withAnimation(.easeIn(duration: 0.25)) {
                                showMainContent = true
                            }
                        }
                    }
                )
                .padding(PanelLayoutMetrics.onboardingInset)
                .transition(.opacity)
            }

            if showWhatsNew, let release = WhatsNewCatalog.release(for: WhatsNewCatalog.currentVersion) {
                WhatsNewView(release: release, onContinue: dismissWhatsNew)
                    .padding(PanelLayoutMetrics.onboardingInset)
                    .transition(.opacity)
                    .onAppear { tvRef.value?.window?.makeFirstResponder(nil) }
            }
        }
    }

    /// Kept out of `fullContent` so the native popover's generic view tree does
    /// not push `ContentView.body` back over Swift's type-checking time limit.
    private var formattingToolbar: some View {
        ToolbarView(
            onBold:      { applyEditorFormat { $0.applyBold() } },
            onItalic:    { applyEditorFormat { $0.applyItalic() } },
            onUnderline: { applyEditorFormat { $0.applyUnderline() } },
            onStrikethrough: { applyEditorFormat { $0.applyStrikethrough() } },
            onBullet:    { applyEditorCursorAction { $0.applyBullet($1) } },
            onTodo:      { applyEditorCursorAction { $0.applyTodo($1) } },
            onLink:      { showLinkDialogFromToolbar() },
            isBugReport: isBugReport,
            linkPopover: LinkPopoverPresentation(
                isPresented: $showLinkDialog,
                content: {
                    AnyView(linkDialogContent)
                }
            )
        )
    }

    private var linkDialogContent: some View {
        LinkDialog(
            context: linkDialogContext,
            onCancel: { dismissLinkDialog(restoringSelection: true) },
            onInsert: { text, url in
                tvRef.value?.insertLink(
                    text: text,
                    url: url,
                    at: linkDialogContext.range
                )
                dismissLinkDialog(restoringSelection: false)
            }
        )
    }

    private var usesDarkAppearance: Bool {
        switch settings.theme {
        case .light:
            return false
        case .dark:
            return true
        case .system:
            return colorScheme == .dark
        }
    }

    private var minimizedContent: some View {
        MinimizedNotePillView(
            title: displayTitle,
            theme: settings.theme,
            onRestore: onRestoreFromMinimized
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Bindings

    private var titleBinding: Binding<String> {
        Binding(
            get: { noteStore.currentNote?.title ?? "" },
            set: { noteStore.saveTitle($0) }
        )
    }

    private var displayTitle: String {
        PanelLayoutMetrics.minimizedDisplayTitle(noteStore.currentNote?.title ?? "")
    }

    private var minimizedWidth: CGFloat {
        PanelLayoutMetrics.minimizedWindowWidth(forTitle: noteStore.currentNote?.title ?? "")
    }

    /// Any overlay panel that covers the editor and should block window drags.
    private var isEditorCoveredByPanel: Bool {
        showSettings || showShortcuts || showAllNotes || isLinkDialogPresented || isConfirmingDelete
    }

    /// The editor's I-beam tracking area bleeds through SwiftUI overlays, so it
    /// is suppressed at the source whenever anything covers the editor.
    private var suppressesEditorCursor: Bool {
        isEditorCoveredByPanel || showOnboarding || showWhatsNew
    }

    private var activeFooterOverlayHeight: CGFloat? {
        // Checked first: the status item menu can open Settings *underneath*
        // the splash, and that must not take over the panel height.
        if showWhatsNew || isDismissingWhatsNew { return PanelLayoutMetrics.whatsNewOverrideHeight }
        if showOnboarding { return PanelLayoutMetrics.onboardingOverrideHeight }
        if showSettings   { return PanelLayoutMetrics.settingsOverrideHeight }
        if showShortcuts  { return PanelLayoutMetrics.shortcutsOverrideHeight }
        return nil
    }

    private var isLinkDialogPresented: Bool {
        showLinkDialog || showSelectionLinkDialog
    }

    /// Either confirmation dialog is up. Both blur the panel and block the
    /// shortcuts and corner controls behind them.
    private var isConfirmingDelete: Bool {
        pendingDeleteNote != nil || pendingDeleteFolder != nil
    }

    private var canUseCornerResizeControls: Bool {
        !panelPresentation.isMinimized
            && showMainContent
            && !showOnboarding
            && !showWhatsNew
            && !showShortcuts
            && !isLinkDialogPresented
            && !isConfirmingDelete
    }

    // Dismissal beats, in order. Same choreography as the onboarding exit, just
    // tighter: this is a dismissal, not a first-run ceremony.
    /// Splash dissolves to an empty panel.
    private var whatsNewFadeDuration: TimeInterval { 0.6 }
    /// `AppDelegate.applyOverrideHeight` resizes over 0.25s; wait a hair longer.
    private var whatsNewResizeDuration: TimeInterval { 0.3 }

    private var isBugReport: Bool {
        bugReportNoteID != nil && bugReportNoteID == noteStore.currentNote?.id
    }

    /// Suppress the update bubble whenever another overlay or transient mode owns
    /// the bottom edge, so it never stacks on top of them.
    private var canShowUpdateBubble: Bool {
        !showOnboarding && !showWhatsNew && !showSettings && !showShortcuts && !showAllNotes
            && !isLinkDialogPresented && !isBugReport && !isConfirmingDelete
    }

    // MARK: - Actions

    /// Marks the running version as seen and fades the splash out. The write
    /// happens on Continue, not on show, so quitting without acknowledging it
    /// brings the splash back next launch.
    private func dismissWhatsNew() {
        guard showWhatsNew else { return }
        settings.lastSeenWhatsNewVersion = WhatsNewCatalog.currentVersion
        settings.save()

        tvRef.value?.suppressesIBeamCursor = isEditorCoveredByPanel

        // Exactly the onboarding exit. The editor's toolbar and footer overhang
        // the window during an animated resize, so the editor must not be on
        // screen for any of it: hide it now (invisible, the opaque splash is
        // still covering everything), dissolve the splash to an empty panel,
        // resize that empty panel, and only then fade the editor back in.
        showMainContent = false
        isDismissingWhatsNew = true
        // Pure crossfades, so they are left ungated by BuoyMotion on purpose.
        withAnimation(.easeInOut(duration: whatsNewFadeDuration)) { showWhatsNew = false }

        // Beat 2: panel is empty, let it resize.
        DispatchQueue.main.asyncAfter(deadline: .now() + whatsNewFadeDuration) {
            isDismissingWhatsNew = false
        }

        // Beat 3: panel is the right size, bring the editor back.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + whatsNewFadeDuration + whatsNewResizeDuration
        ) {
            withAnimation(.easeIn(duration: 0.25)) { showMainContent = true }
            guard !panelPresentation.isMinimized else { return }
            focusEditor()
        }
    }

    private func createNote() {
        guard !showWhatsNew else { return }
        noteStore.createNote()
        // Signal HeaderView to focus + select the title field
        focusTitleTrigger.toggle()
    }

    private func navigateNote(forward: Bool) {
        guard !showWhatsNew else { return }
        let previousID = noteStore.currentNote?.id
        if forward { noteStore.nextNote() } else { noteStore.previousNote() }
        if previousID != noteStore.currentNote?.id {
            slideDirection = noteStore.lastNavigationDirection
            withAnimation(BuoyMotion.spring(response: 0.3, dampingFraction: 0.8)) {
                slideID = UUID()
            }
        }
        focusEditor()
    }

    private func persistCurrentNoteSelection(_ noteID: String?) {
        guard settings.lastSelectedNoteID != noteID else { return }
        settings.lastSelectedNoteID = noteID
    }

    private func dismissTransientUI() {
        // Harbor Mode unmounts the splash and restores at compact height, which
        // would clip it. WhatsNewView swallows ⌘M, but the Window menu item in
        // Dock mode reaches minimize without passing through that monitor.
        dismissWhatsNew()
        // The system popover owns its materialize/dematerialize animation and
        // its Reduce Motion adaptation; don't wrap that state change ourselves.
        selectionLinkPopoverController.dismiss()
        showSelectionLinkDialog = false
        showLinkDialog = false
        withAnimation(BuoyMotion.easeOut(0.16)) {
            showAllNotes = false
            showSettings = false
            showShortcuts = false
        }
    }

    private func toggleAllNotes() {
        guard !showWhatsNew else { return }
        withAnimation(BuoyMotion.easeOut(0.16)) {
            showAllNotes.toggle()
            if showAllNotes { showSettings = false; showShortcuts = false }
        }
        if !showAllNotes { focusEditor() }
    }

    private func toggleSettings() {
        guard !showWhatsNew else { return }
        withAnimation(BuoyMotion.easeOut(0.16)) {
            showSettings.toggle()
            if showSettings { showAllNotes = false; showShortcuts = false }
        }
        if !showSettings { focusEditor() }
    }

    private func toggleShortcuts() {
        guard !showWhatsNew else { return }
        withAnimation(BuoyMotion.easeOut(0.16)) {
            showShortcuts.toggle()
            if showShortcuts { showAllNotes = false; showSettings = false }
        }
        if !showShortcuts { focusEditor() }
    }

    private func deleteCurrentNote() {
        guard !showWhatsNew else { return }
        guard let note = noteStore.currentNote else { return }
        requestDeleteNote(note)
    }

    /// Entry point for both delete paths (⌘⌫ and the All Notes panel).
    /// Validates the "last note" guard, then defers to the confirmation dialog.
    private func requestDeleteNote(_ note: Note) {
        guard noteStore.notes.count > 1 else {
            toastState.show("Cannot delete the last note", style: .error)
            return
        }
        withAnimation(BuoyMotion.easeOut(0.16)) { pendingDeleteNote = note }
    }

    private func confirmDeleteNote() {
        guard let note = pendingDeleteNote else { return }
        withAnimation(BuoyMotion.easeOut(0.16)) { pendingDeleteNote = nil }
        noteStore.deleteNote(note)
        focusEditor()
    }

    private func cancelDeleteNote() {
        withAnimation(BuoyMotion.easeOut(0.16)) { pendingDeleteNote = nil }
        focusEditor()
    }

    /// Deleting a folder never deletes a note — its notes are simply unfiled
    /// and stay in the All Notes section — but it is still destructive enough
    /// to confirm, since the grouping itself cannot be recovered.
    private func requestDeleteFolder(_ folder: Folder) {
        renamingFolderID = nil
        withAnimation(BuoyMotion.easeOut(0.16)) { pendingDeleteFolder = folder }
    }

    private func confirmDeleteFolder() {
        guard let folder = pendingDeleteFolder else { return }
        withAnimation(BuoyMotion.easeOut(0.16)) { pendingDeleteFolder = nil }
        noteStore.deleteFolder(folder.id)
        focusEditor()
    }

    private func cancelDeleteFolder() {
        withAnimation(BuoyMotion.easeOut(0.16)) { pendingDeleteFolder = nil }
        focusEditor()
    }

    private func focusEditor() {
        DispatchQueue.main.async { [tv = tvRef.value] in
            tv?.window?.makeFirstResponder(tv)
        }
    }

    private func applyEditorFormat(_ action: @escaping (BuoyTextView) -> Void) {
        guard let tv = tvRef.value else { return }
        tv.window?.makeFirstResponder(tv)
        DispatchQueue.main.async {
            if tv.lastKnownSelection.length > 0 {
                tv.setSelectedRange(tv.lastKnownSelection)
            }
            action(tv)
        }
    }

    private func applyEditorCursorAction(_ action: @escaping (BuoyTextView, NSRange) -> Void) {
        guard let tv = tvRef.value else { return }
        let pos = tv.lastKnownCursorPosition
        tv.window?.makeFirstResponder(tv)
        DispatchQueue.main.async { action(tv, pos) }
    }

    private func showLinkDialogFromToolbar() {
        presentLinkDialog(tvRef.value?.linkEditingContext() ?? .empty)
    }

    private func presentLinkDialog(_ context: LinkEditingContext) {
        guard !showWhatsNew else { return }
        linkDialogContext = context
        showLinkDialog = false

        guard let highlightedRange = context.highlightedRange,
              let textView = tvRef.value,
              let anchorRect = textView.linkPopoverAnchorRect(for: highlightedRange) else {
            selectionLinkPopoverController.dismiss()
            showSelectionLinkDialog = false
            showLinkDialog = true
            return
        }

        showSelectionLinkDialog = true
        let presentation = $showSelectionLinkDialog
        selectionLinkPopoverController.onClose = {
            presentation.wrappedValue = false
        }
        selectionLinkPopoverController.present(
            content: AnyView(linkDialogContent),
            relativeTo: anchorRect,
            of: textView
        )
    }

    private func dismissLinkDialog(restoringSelection: Bool) {
        let context = linkDialogContext
        selectionLinkPopoverController.dismiss()
        showSelectionLinkDialog = false
        showLinkDialog = false
        guard restoringSelection, let tv = tvRef.value else { return }
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(context.range)
        }
    }

    /// Live text from the editor when it is mounted, falling back to the stored
    /// RTF. The editor is authoritative because it holds edits that have not hit
    /// their debounce yet.
    private var currentPlainText: String {
        if let tv = tvRef.value { return tv.plainTextContent() }
        return noteStore.currentNote.map(NotePlainText.of) ?? ""
    }

    private func copyToClipboard() {
        let text = currentPlainText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        toastState.show("Copied to clipboard")
    }

    private func cancelBugReport() {
        guard let note = noteStore.currentNote, isBugReport else { return }
        bugReportNoteID = nil
        noteStore.discardNote(note)
        focusEditor()
    }

    private func createBugReportNote() {
        withAnimation(BuoyMotion.easeOut(0.16)) { showSettings = false }
        // Titled at insert rather than through the debounced saveTitle path: the
        // note is discarded on Cancel or Send, and a title still in flight then
        // is a write aimed at a deleted row. It also keeps the scratch note from
        // consuming a number in the "Note N" sequence.
        noteStore.createNote(titled: "Bug Report")
        bugReportNoteID = noteStore.currentNote?.id
        focusEditor()
    }

    private func sendBugReport() {
        guard let note = noteStore.currentNote, isBugReport else { return }
        let text = currentPlainText
        bugReportNoteID = nil
        noteStore.discardNote(note)

        var components = URLComponents(string: "https://tally.so/r/J98A7K")!
        components.queryItems = [URLQueryItem(name: "report", value: text)]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func transferToAppleNotes() {
        let html = tvRef.value?.htmlContent() ?? ""
        AppleNotesService.transfer(htmlContent: html) { error in
            if let error {
                toastState.show("Error: \(error)", style: .error)
            } else {
                toastState.show("Transferred to Apple Notes")
            }
        }
    }

    private func electronToSymbols(_ s: String) -> String {
        s.replacingOccurrences(of: "Cmd",    with: "⌘")
         .replacingOccurrences(of: "Ctrl",   with: "⌃")
         .replacingOccurrences(of: "Option", with: "⌥")
         .replacingOccurrences(of: "Shift",  with: "⇧")
         .replacingOccurrences(of: "+",      with: "")
    }
}
