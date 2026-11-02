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
    /// A note whose editor should take focus as soon as it mounts. See
    /// `focusEditor()`.
    var pendingFocusNoteID: String?
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
    /// Restores regular size when the empty top bar is double-clicked.
    var onRestorePanelSize: ((CGSize) -> Void)?
    var onClose: () -> Void
    var onMinimize: () -> Void
    var onExpand: () -> Void
    var onRestoreFromMinimized: () -> Void

    // Panel visibility
    @State private var showAllNotes = false
    /// The Settings popover, anchored to the footer's gear.
    @State private var showSettings = false

    /// Controls and editor scale directly with the available window size.
    @State private var chromeCompactness: CGFloat = 0

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
    /// A note switch normally clears the toast. Following a note link sets
    /// this to the target first, so its Go Back toast survives the switch.
    @State private var toastKeptForNoteID: String? = nil

    // Find in note (⌘F)
    @State private var findController = NoteFindController()

    /// Which All Notes row the arrow keys have highlighted, so ⌘⌫ can delete
    /// that note instead of the one open in the editor.
    @State private var allNotesKeyboard = AllNotesKeyboardController()

    // Text view reference for toolbar actions — @StateObject persists across all re-renders
    @State private var tvRef = TextViewRef()
    /// What the toolbar draws pressed in. Lives here, not in the editor,
    /// because the editor remounts on every note switch.
    @State private var formattingState = EditorFormattingState()

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
        onRestorePanelSize: ((CGSize) -> Void)? = nil,
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
        self.onRestorePanelSize = onRestorePanelSize
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
                    // Folding in, the window's own shrink is the motion; the
                    // outgoing panel only fades. Scaling it as well stacked a
                    // second movement on the crop and put the editor's AppKit
                    // views under a per-frame transform.
                    .transition(.asymmetric(
                        insertion: BuoyMotion.transition(.scale(scale: 0.7, anchor: .center).combined(with: .opacity)),
                        removal: .opacity
                    ))
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
            // Only steal focus if nothing meaningful is already focused
            if !Self.isTextInputFocused(tvRef.value?.window?.firstResponder) {
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
            .buoyToggleAllNotes:  { toggleAllNotes() },
            .buoyInsertLink:      { showLinkDialogFromToolbar() },
            .buoyFindInNote:      { presentFind() },
            .buoyOpenNoteLink:    { openLinkedNote() },
            .openSettings:        { toggleSettings() },
            // Posted by AppDelegate once the restore's frame animation lands.
            .buoyHarborRestoreFinished: {
                guard !showOnboarding, !showWhatsNew else { return }
                focusEditor()
            },
            .buoyAutoTitleFailed: { toastState.show("Couldn't name this note", style: .warning) },
            .buoyAutoTitleUnsupportedLanguage: { toastState.show("Auto-naming isn't available for this note", style: .warning) },
            .buoyBackupFailed: { toastState.show("Couldn't back up notes before updating", style: .warning, duration: 6) },
            .buoyMigrationFailed: { toastState.show("Buoy couldn't update its notes database", style: .error, duration: 8) },
            // One-time tip; `.info` gives it the same length as the Harbor timer tip.
            .buoyFocusFogDidShow: {
                guard !settings.hasSeenFocusFogTip else { return }
                settings.hasSeenFocusFogTip = true
                toastState.show("Shake the window to exit Fog Mode", style: .info)
            }
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
                // A one-time tip: shown the first time a restore leaves a
                // timer running, never again.
                if currentHarborTimer.isActive, !settings.hasSeenHarborTimerTip {
                    let timerNoteID = noteStore.currentNote?.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + PanelLayoutMetrics.minimizedFrameAnimationDuration + 0.12) {
                        guard !panelPresentation.isMinimized,
                              !settings.hasSeenHarborTimerTip,
                              noteStore.currentNote?.id == timerNoteID,
                              currentHarborTimer.isActive else { return }
                        settings.hasSeenHarborTimerTip = true
                        toastState.show("Manage timers in Harbor Mode", style: .info)
                    }
                }
            }
        }
        .onChange(of: displayTitle) { _, _ in
            // Renaming a note whose timer already ran out clears "Time's up",
            // so the pill shows the new title rather than a stale finish.
            if currentHarborTimer.isFinished { currentHarborTimer.stop() }
            onMinimizedWidthChange?(minimizedWidth)
        }
        .onChange(of: currentHarborTimer.isActive) { _, _ in
            guard panelPresentation.isMinimized else { return }
            onMinimizedWidthChange?(minimizedWidth)
        }
        .onChange(of: noteStore.currentNote?.id) { _, noteID in
            persistCurrentNoteSelection(noteID)
            if noteID != toastKeptForNoteID { toastState.dismiss() }
            toastKeptForNoteID = nil
            findController.dismiss(focusingEditor: false)
            onMinimizedWidthChange?(minimizedWidth)
        }
        .onChange(of: Set(noteStore.notes.map(\.id))) { _, noteIDs in
            panelPresentation.removeHarborTimers(except: noteIDs)
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
            .modifier(HarborTransitionLayout(
                size: panelPresentation.harborTransitionGlassSize,
                alignment: panelPresentation.harborTransitionAlignment
            ))
            // Minimums *and* maximums. With only a minimum, SwiftUI hands the
            // content its ideal size — the widest bar, about 244pt — and then
            // merely refuses to go below the floor. That looked correct only
            // while the floor happened to equal the window's own minimum; the
            // moment compact chrome lowered the floor, the content sat at 244
            // inside a 316pt panel with the difference showing as dead space
            // down the right and along the bottom.
            .frame(
                // Always the compact floor, never the current density's. AppKit
                // already refuses to shrink the window below this, and pinning
                // the SwiftUI minimum to the live density would clip the content
                // for the one frame between the window shrinking and the density
                // catching up. Dropped during the Harbor sweep, where the glass
                // has to follow a window smaller than any floor.
                minWidth: isHarborTransitioning ? 0 : PanelLayoutMetrics.minimumGlassWidth(for: .compact),
                maxWidth: .infinity,
                minHeight: isHarborTransitioning ? 0 : PanelLayoutMetrics.minimumGlassHeight(for: .compact),
                maxHeight: .infinity
            )
            // Reads the window size itself, so a resize re-renders only the
            // reader rather than invalidating the whole of this body per frame.
            .background(ChromeDensityReader(compactness: $chromeCompactness, presentation: panelPresentation))
            .background(WindowDragBlocker())
            .overlay { deleteConfirmOverlay }
            .buoyGlass()
            // Applied outermost on purpose. `.environment` reaches the modified
            // view and everything *inside* it, so setting it above `.buoyGlass`
            // leaves the glass itself — an ancestor — reading the defaults, and
            // the window tint silently does nothing.
            .environment(\.chromeMetrics, chromeMetrics)
            .environment(\.buoyTheme, buoyTheme)
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
            .environment(\.buoyTheme, buoyTheme)
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
                    onHeaderDoubleClick: {
                        guard !showOnboarding, !showWhatsNew else { return }
                        onRestorePanelSize?(CGSize(
                            width: PanelLayoutMetrics.regularChromeWindowWidth,
                            height: PanelLayoutMetrics.regularChromeWindowHeight
                        ))
                    },
                    dragEnabled: !showAllNotes && !isLinkDialogPresented,
                    isBugReport: isBugReport,
                    titleReveal: noteStore.titleReveal,
                    onRevealFinished: { noteStore.titleReveal = nil },
                    titleThinking: noteStore.titleThinking != nil && noteStore.titleThinking == noteStore.currentNote?.id,
                    // Only while counting down. Once it reads "Time's up" the
                    // title is the note's own again and can be edited.
                    timerTitle: currentHarborTimer.isActive && !currentHarborTimer.isFinished
                        ? currentHarborTimer.displayText : nil,
                    isTimerPaused: currentHarborTimer.isPaused,
                    onTimerTitleClick: onMinimize
                )

                formattingToolbar

                if let note = noteStore.currentNote {
                    EditorView(
                        rtfData: note.contentRTF,
                        fontSize: settings.fontSize,
                        magnification: chromeMetrics.editorMagnification,
                        isResizingByDrag: panelPresentation.isResizingByDrag,
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
                        textViewRef: { tv in configureEditor(tv) }
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: chromeMetrics.editorMinimumHeight,
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
                    isSettingsPresented: $showSettings,
                    settings: $settings,
                    onReportBug: createBugReportNote,
                    onQuit: { NSApp.terminate(nil) },
                    onTransferToAppleNotes: transferToAppleNotes,
                    onCopy: copyToClipboard,
                    isBugReport: isBugReport,
                    onSendBugReport: sendBugReport,
                    onCancelBugReport: cancelBugReport,
                    folderName: currentFolderName,
                    onFolderClick: toggleAllNotes
                )
                .onChange(of: noteStore.currentNote?.id) { _, _ in
                    editorSelectedText = ""
                }
            }
            .opacity(showMainContent ? 1 : 0)

            if showAllNotes {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(BuoyMotion.easeOut(0.16)) { showAllNotes = false }
                        focusEditor()
                    }
            }

            AllNotesOverlay(
                isShowing: $showAllNotes,
                noteStore: noteStore,
                keyboard: allNotesKeyboard,
                renamingFolderID: $renamingFolderID,
                onDeleteNote: { note in requestDeleteNote(note) },
                onDeleteFolder: { folder in requestDeleteFolder(folder) },
                onFocusEditor: { focusEditor() }
            )

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
        .overlay {
            ToastContainer(state: toastState)
        }
    }

    /// Kept out of `fullContent` so the native popover's generic view tree does
    /// not push `ContentView.body` back over Swift's type-checking time limit.
    ///
    /// The find bar takes the toolbar's place while it is open rather than
    /// stacking above the editor: the note doesn't jump down by a row, and
    /// nobody formats text mid-search.
    @ViewBuilder
    private var formattingToolbar: some View {
        if findController.isPresented {
            NoteFindBar(controller: findController)
                .padding(.horizontal, 8)
                .transition(.opacity)
        } else {
            editingToolbar
                .transition(.opacity)
        }
    }

    private var editingToolbar: some View {
        ToolbarView(
            onBold:      { applyEditorFormat { $0.applyBold() } },
            onItalic:    { applyEditorFormat { $0.applyItalic() } },
            onUnderline: { applyEditorFormat { $0.applyUnderline() } },
            onStrikethrough: { applyEditorFormat { $0.applyStrikethrough() } },
            onBullet:    { applyEditorCursorAction { $0.applyBullet($1) } },
            onTodo:      { applyEditorCursorAction { $0.applyTodo($1) } },
            onLink:      { showLinkDialogFromToolbar() },
            linkPopover: LinkPopoverPresentation(
                isPresented: $showLinkDialog,
                content: {
                    AnyView(linkDialogContent)
                }
            ),
            formattingState: formattingState,
            isLinkDialogOpen: isLinkDialogPresented
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

    private var isHarborTransitioning: Bool {
        panelPresentation.harborTransitionGlassSize != nil
    }

    private var chromeMetrics: ChromeMetrics {
        ChromeMetrics(compactness: chromeCompactness)
    }

    private var buoyTheme: BuoyTheme {
        BuoyTheme(settings: settings)
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
            timer: currentHarborTimer,
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

    /// The folder the open note is filed in, for the footer's folder label.
    private var currentFolderName: String? {
        guard let folderID = noteStore.currentNote?.folderID, !isBugReport else { return nil }
        return noteStore.folders.first { $0.id == folderID }?.displayName
    }

    private var displayTitle: String {
        PanelLayoutMetrics.minimizedDisplayTitle(noteStore.currentNote?.title ?? "")
    }

    private var currentHarborTimer: HarborTimer {
        panelPresentation.harborTimer(for: noteStore.currentNote?.id)
    }

    private var minimizedWidth: CGFloat {
        currentHarborTimer.isActive
            ? PanelLayoutMetrics.minimizedTimerWindowWidth
            : PanelLayoutMetrics.minimizedWindowWidth(forTitle: noteStore.currentNote?.title ?? "")
    }

    /// Any overlay panel that covers the editor and should block window drags.
    private var isEditorCoveredByPanel: Bool {
        showAllNotes || isLinkDialogPresented || isConfirmingDelete
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
        !showOnboarding && !showWhatsNew && !showAllNotes
            && !isLinkDialogPresented && !isBugReport && !isConfirmingDelete
            // Both pills sit on the same spot; a toast takes it for its few seconds.
            && !toastState.isShowing
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
        // Set ahead, in its own update, so the outgoing editor's removal
        // transition already points the right way.
        slideDirection = forward ? .forward : .backward
        // The switch and the new identity in one transaction (see
        // `slideToNote`).
        withAnimation(BuoyMotion.spring(response: 0.3, dampingFraction: 0.8)) {
            if forward { noteStore.nextNote() } else { noteStore.previousNote() }
            if previousID != noteStore.currentNote?.id {
                slideID = UUID()
            }
        }
        focusEditor()
    }

    /// Runs on every editor update, so everything here must be cheap and
    /// idempotent. Kept out of `body`, which is at the type-checker limit.
    private func configureEditor(_ tv: BuoyTextView) {
        tvRef.value = tv
        NoteIntentBridge.editor = tv
        tv.formattingState = formattingState
        tv.suppressesIBeamCursor = suppressesEditorCursor
        if let pending = tvRef.pendingFocusNoteID, tv.noteID == pending {
            tvRef.pendingFocusNoteID = nil
            // Not in its window yet when this runs from `makeNSView`.
            DispatchQueue.main.async { [weak tv] in
                tv?.window?.makeFirstResponder(tv)
            }
        }
        if tv.noteLinkSuggestions == nil {
            let store = noteStore
            tv.noteLinkSuggestions = {
                store.recentNotes(excluding: store.currentNote?.id, limit: .max).map {
                    let title = $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    return NoteLinkSuggestion(noteID: $0.id, title: title.isEmpty ? "Untitled" : title)
                }
            }
        }
    }

    /// A `>>` link was clicked: slide over to its note, the way the next
    /// note slides in, and offer the way back in a toast.
    private func openLinkedNote() {
        guard !showWhatsNew, !showOnboarding, let id = NoteLink.takePendingNoteID() else { return }
        guard let note = noteStore.notes.first(where: { $0.id == id }) else {
            toastState.show("Couldn't find that note", style: .warning)
            return
        }
        guard let source = noteStore.currentNote, note.id != source.id else { return }
        toastKeptForNoteID = note.id
        slideToNote(note, direction: .forward)
        toastState.show(
            "Linked from \(Self.toastTitle(source.title))",
            style: .info,
            actionTitle: "Go Back"
        ) {
            // The source may have been deleted while the toast was up.
            guard let back = noteStore.notes.first(where: { $0.id == source.id }),
                  back.id != noteStore.currentNote?.id else { return }
            slideToNote(back, direction: .backward)
        }
    }

    private func slideToNote(_ note: Note, direction: NavigationDirection) {
        if showAllNotes {
            withAnimation(BuoyMotion.easeOut(0.16)) { showAllNotes = false }
        }
        slideDirection = direction
        // The note switch and the new identity must land in one transaction.
        // Switching first, outside it, made SwiftUI point the *outgoing*
        // editor at the new note (so the slide-out showed the wrong note),
        // and that outgoing view claimed the note's kept editor from
        // `EditorCache`. The incoming view then got a fresh editor with no
        // undo history, and focus left with the outgoing one.
        withAnimation(BuoyMotion.spring(response: 0.3, dampingFraction: 0.8)) {
            noteStore.switchNote(to: note)
            slideID = UUID()
        }
        focusEditor()
    }

    /// A note title short enough to sit in a one-line toast beside its action.
    private static func toastTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled" }
        return trimmed.count > 22 ? "\(trimmed.prefix(21))…" : trimmed
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
        toastState.dismiss()
        findController.dismiss(focusingEditor: false)
        withAnimation(BuoyMotion.easeOut(0.16)) { showAllNotes = false }
    }

    /// Field editors count: the title, the All Notes search and the find bar
    /// are all edited through one, and none of them is an `NSTextField`.
    private static func isTextInputFocused(_ responder: NSResponder?) -> Bool {
        if responder is BuoyTextView || responder is NSTextField { return true }
        return (responder as? NSTextView)?.isFieldEditor == true
    }

    private func presentFind() {
        guard !showWhatsNew, !showOnboarding, !panelPresentation.isMinimized else { return }
        if showAllNotes {
            withAnimation(BuoyMotion.easeOut(0.16)) { showAllNotes = false }
        }
        withAnimation(BuoyMotion.easeOut(0.16)) {
            findController.present(for: tvRef.value)
        }
    }

    private func toggleSettings() {
        guard !showWhatsNew, !showOnboarding else { return }
        showSettings.toggle()
    }

    private func toggleAllNotes() {
        guard !showWhatsNew else { return }
        withAnimation(BuoyMotion.easeOut(0.16)) { showAllNotes.toggle() }
        if !showAllNotes { focusEditor() }
    }

    private func deleteCurrentNote() {
        guard !showWhatsNew else { return }
        // In All Notes, ⌘⌫ means the row the arrow keys are on, the same way
        // it means the selected file in Finder.
        if showAllNotes, let highlighted = allNotesKeyboard.highlightedNote {
            requestDeleteNote(highlighted)
            return
        }
        guard let note = noteStore.currentNote else { return }
        requestDeleteNote(note)
    }

    /// Entry point for both delete paths (⌘⌫ and the All Notes panel).
    /// Validates the "last note" guard, then defers to the confirmation dialog.
    private func requestDeleteNote(_ note: Note) {
        guard noteStore.notes.count > 1 else {
            toastState.show("Can't delete the last note", style: .error)
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

    /// Focuses the current note's editor, including one that hasn't mounted
    /// yet. After a note switch the new editor only appears in a coming
    /// SwiftUI update, and a plain `async` ran before it, focusing the editor
    /// of the note being left. ⌘Z is handled only by the focused editor, so
    /// it reached the wrong note and undo did nothing after Go Back. The
    /// request is keyed to the note: whichever happens first, this block or
    /// the editor mounting (`configureEditor`), focuses the right one.
    private func focusEditor() {
        let target = noteStore.currentNote?.id
        tvRef.pendingFocusNoteID = target
        DispatchQueue.main.async { [tvRef] in
            guard let tv = tvRef.value, tv.noteID == target, tv.window != nil else { return }
            tvRef.pendingFocusNoteID = nil
            tv.window?.makeFirstResponder(tv)
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
        guard !showWhatsNew else { return }
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

    /// The service's message is an AppleScript or file error, too long and
    /// too technical for a one-line pill; log it and say what failed.
    private func showTransferError(_ error: String) {
        NSLog("Buoy: Apple Notes transfer failed: %@", error)
        toastState.show("Couldn't transfer to Apple Notes", style: .error)
    }

    private func transferToAppleNotes() {
        guard let textView = tvRef.value else { return }
        if #available(macOS 26, *) {
            let markdown = textView.markdownContent(title: noteStore.currentNote?.title ?? "Untitled")
            AppleNotesService.transferMarkdown(markdown) { error in
                if let error {
                    showTransferError(error)
                } else {
                    toastState.show("Confirm the import in Apple Notes", style: .info)
                }
            }
            return
        }
        let html = textView.htmlContent()
        AppleNotesService.transfer(htmlContent: html) { error in
            if let error {
                showTransferError(error)
            } else {
                toastState.show("Transferred to Apple Notes")
            }
        }
    }

}
