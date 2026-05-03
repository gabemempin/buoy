import SwiftUI
import AppKit

// Class wrapper so the NSTextView reference survives SwiftUI re-renders without triggering update cycles.
private final class TextViewRef {
    var value: BuoyTextView?
}

struct ContentView: View {
    var noteStore: NoteStore
    var panelPresentation: PanelPresentationModel
    @Binding var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    var onHeightChange: ((CGFloat) -> Void)?
    var onNoteSwitchHeight: ((CGFloat) -> Void)?
    var onOnboardingComplete: (() -> Void)?
    var onOverrideHeight: ((CGFloat?) -> Void)?
    var onMinimizedWidthChange: ((CGFloat) -> Void)?
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
    @State private var linkDialogSelectedText = ""

    // Toast
    @State private var toastState = ToastState()

    // Text view reference for toolbar actions — @StateObject persists across all re-renders
    @State private var tvRef = TextViewRef()

    // Navigation slide state
    @State private var slideDirection: NavigationDirection? = nil
    @State private var slideID = UUID()

    // Title focus trigger
    @State private var focusTitleTrigger = false

    // Cursor position captured before link dialog opens (avoids stale selection overwriting it)
    @State private var savedInsertionPoint: NSRange = NSRange(location: 0, length: 0)

    // Tracks the editor's current selection for the footer word/char count
    @State private var editorSelectedText: String = ""
    @State private var showOnboarding: Bool
    @State private var showMainContent: Bool

    init(
        noteStore: NoteStore,
        panelPresentation: PanelPresentationModel,
        settings: Binding<AppSettings>,
        onHeightChange: ((CGFloat) -> Void)?,
        onNoteSwitchHeight: ((CGFloat) -> Void)? = nil,
        onOnboardingComplete: (() -> Void)? = nil,
        onOverrideHeight: ((CGFloat?) -> Void)? = nil,
        onMinimizedWidthChange: ((CGFloat) -> Void)? = nil,
        onClose: @escaping () -> Void,
        onMinimize: @escaping () -> Void,
        onExpand: @escaping () -> Void,
        onRestoreFromMinimized: @escaping () -> Void
    ) {
        self.noteStore = noteStore
        self.panelPresentation = panelPresentation
        self._settings = settings
        self.onHeightChange = onHeightChange
        self.onNoteSwitchHeight = onNoteSwitchHeight
        self.onOnboardingComplete = onOnboardingComplete
        self.onOverrideHeight = onOverrideHeight
        self.onMinimizedWidthChange = onMinimizedWidthChange
        self.onClose = onClose
        self.onMinimize = onMinimize
        self.onExpand = onExpand
        self.onRestoreFromMinimized = onRestoreFromMinimized
        self._showOnboarding = State(initialValue: !settings.wrappedValue.onboarded)
        self._showMainContent = State(initialValue: settings.wrappedValue.onboarded)
    }

    var body: some View {
        ZStack {
            if panelPresentation.isMinimized {
                minimizedPanelContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                fullPanelContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: PanelLayoutMetrics.minimizedTransitionDuration), value: panelPresentation.isMinimized)
        // Auto-focus the editor when the panel becomes key (fixes macOS 15 where
        // NSHostingView doesn't automatically route keyboard events to the text view).
        .onReceive(NotificationCenter.default.publisher(for: .buoyPanelBecameKey)) { _ in
            guard !panelPresentation.isMinimized else { return }
            let fr = tvRef.value?.window?.firstResponder
            // Only steal focus if nothing meaningful is already focused
            if !(fr is BuoyTextView || fr is NSTextField) {
                focusEditor()
            }
        }
        // App-level shortcut notifications from BuoyTextView
        .onReceive(NotificationCenter.default.publisher(for: .buoyNewNote))         { _ in createNote() }
        .onReceive(NotificationCenter.default.publisher(for: .buoyDeleteNote))      { _ in deleteCurrentNote() }
        .onReceive(NotificationCenter.default.publisher(for: .buoyCopyToClipboard)) { _ in copyToClipboard() }
        .onReceive(NotificationCenter.default.publisher(for: .buoyPreviousNote))    { _ in
            let previousID = noteStore.currentNote?.id
            noteStore.previousNote()
            if previousID != noteStore.currentNote?.id {
                slideDirection = noteStore.lastNavigationDirection
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    slideID = UUID()
                }
            }
            focusEditor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .buoyNextNote))        { _ in
            let previousID = noteStore.currentNote?.id
            noteStore.nextNote()
            if previousID != noteStore.currentNote?.id {
                slideDirection = noteStore.lastNavigationDirection
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    slideID = UUID()
                }
            }
            focusEditor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLinkDialog)) { notif in
            guard !panelPresentation.isMinimized else { return }
            linkDialogSelectedText = notif.object as? String ?? ""
            withAnimation { showLinkDialog = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            withAnimation(.easeOut(duration: 0.16)) {
                showSettings.toggle()
                if showSettings { showAllNotes = false; showShortcuts = false }
            }
            if !showSettings { focusEditor() }
        }
        // Block window dragging whenever any overlay panel is open
        .onChange(of: showSettings || showShortcuts || showAllNotes) { _, panelOpen in
            NSApp.windows.compactMap { $0 as? NSPanel }.forEach {
                $0.isMovable = !panelOpen
            }
        }
        .onChange(of: panelPresentation.isMinimized) { _, isMinimized in
            if isMinimized {
                dismissTransientUI()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + PanelLayoutMetrics.minimizedFrameAnimationDuration) {
                    guard !panelPresentation.isMinimized else { return }
                    focusEditor()
                }
            }
        }
        .onChange(of: displayTitle) { _, _ in
            onMinimizedWidthChange?(minimizedWidth)
        }
        // Re-measure height when font size changes
        .onChange(of: settings.fontSize) { _, _ in
            guard !panelPresentation.isMinimized else { return }
            if let tv = tvRef.value {
                let h = tv.measureContentHeight()
                onHeightChange?(h + 160)
            }
        }
        .onChange(of: activeFooterOverlayHeight) { _, height in
            onOverrideHeight?(height)
        }
        .onAppear {
            showOnboarding = !settings.onboarded
            onMinimizedWidthChange?(minimizedWidth)
            if showOnboarding { onOverrideHeight?(PanelLayoutMetrics.onboardingOverrideHeight) }
        }
    }

    private var fullPanelContent: some View {
        fullContent
            .padding(PanelLayoutMetrics.windowPadding)
            .frame(
                minWidth: PanelLayoutMetrics.minimumContentWidth,
                minHeight: PanelLayoutMetrics.minimumWindowHeight
            )
            .background(WindowDragBlocker())
            .buoyGlass()
    }

    private var minimizedPanelContent: some View {
        minimizedContent
            .padding(PanelLayoutMetrics.windowPadding)
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
                    dragEnabled: !showSettings && !showShortcuts && !showAllNotes,
                    isBugReport: isBugReport
                )

                ToolbarView(
                    onBold:      { applyEditorFormat { $0.applyBold() } },
                    onItalic:    { applyEditorFormat { $0.applyItalic() } },
                    onUnderline: { applyEditorFormat { $0.applyUnderline() } },
                    onBullet:    { applyEditorCursorAction { $0.applyBullet($1) } },
                    onTodo:      { applyEditorCursorAction { $0.applyTodo($1) } },
                    onLink:      { showLinkDialogFromToolbar() },
                    isBugReport: isBugReport
                )

                if showLinkDialog {
                    LinkDialog(
                        isShowing: $showLinkDialog,
                        selectedText: linkDialogSelectedText
                    ) { text, url in
                        tvRef.value?.insertLink(text: text, url: url, at: savedInsertionPoint)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let note = noteStore.currentNote {
                    EditorView(
                        rtfData: note.contentRTF,
                        fontSize: settings.fontSize,
                        usesDarkAppearance: usesDarkAppearance,
                        noteID: note.id,
                        placeholder: isBugReport
                            ? "Tell me what you want fixed or improved. If something went wrong, detail how to reproduce the bug.\n\nThank you for making Buoy better!"
                            : "Start typing… (⌘← ⌘→ to navigate notes)",
                        onHeightChange: { h in
                            DispatchQueue.main.async {
                                onHeightChange?(h + 160)
                            }
                        },
                        onNoteSwitch: { h in
                            DispatchQueue.main.async {
                                onNoteSwitchHeight?(h + 160)
                            }
                        },
                        onSelectionChange: { text in
                            editorSelectedText = text
                        },
                        onContentChange: { rtf in
                            noteStore.saveContent(rtf)
                        },
                        textViewRef: { tv in
                            tvRef.value = tv
                        }
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: PanelLayoutMetrics.editorMinimumHeight,
                        alignment: .leading
                    )
                    .id(slideID)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: slideDirection == .forward ? .trailing : .leading),
                            removal: .move(edge: slideDirection == .forward ? .leading : .trailing)
                        )
                    )
                }

                FooterView(
                    createdAt: noteStore.currentNote?.createdAt ?? 0,
                    updatedAt: noteStore.currentNote?.updatedAt ?? 0,
                    plainText: noteStore.currentNote.flatMap {
                        NSAttributedString(rtf: $0.contentRTF, documentAttributes: nil)?.string
                    } ?? "",
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
                        withAnimation(.easeOut(duration: 0.16)) {
                            showAllNotes = false
                            showSettings = false
                            showShortcuts = false
                        }
                        focusEditor()
                    }
            }

            GeometryReader { proxy in
                ZStack(alignment: .topTrailing) {
                    if showAllNotes {
                        AllNotesPanel(
                            isShowing: $showAllNotes,
                            notes: noteStore.notes,
                            currentNoteID: noteStore.currentNote?.id,
                            onSelect: { note in
                                noteStore.switchNote(to: note)
                                focusEditor()
                            },
                            onDelete: { note in
                                guard noteStore.notes.count > 1 else {
                                    toastState.show("Cannot delete the last note", isError: true)
                                    return
                                }
                                noteStore.deleteNote(note)
                            }
                        )
                        .frame(
                            maxHeight: max(
                                CGFloat.zero,
                                proxy.size.height
                                    - PanelLayoutMetrics.allNotesTopInset
                                    - PanelLayoutMetrics.allNotesBottomInset
                            ),
                            alignment: .top
                        )
                        .padding(.top, PanelLayoutMetrics.allNotesTopInset)
                        .padding(.trailing, PanelLayoutMetrics.overlayHorizontalInset)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .animation(.easeOut(duration: 0.16), value: showAllNotes)
            .allowsHitTesting(showAllNotes)

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
            .animation(.easeOut(duration: 0.16), value: showSettings)
            .animation(.easeOut(duration: 0.16), value: showShortcuts)
            .allowsHitTesting(showSettings || showShortcuts)

            if showOnboarding {
                OnboardingView(
                    settings: $settings,
                    onShortcutChanged: { s in HotkeyService.shared.register(shortcut: s) },
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 1.0)) {
                            showOnboarding = false
                        }
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
                .padding(2)
                .transition(.opacity)
            }
        }
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

    private var activeFooterOverlayHeight: CGFloat? {
        if showOnboarding { return PanelLayoutMetrics.onboardingOverrideHeight }
        if showSettings   { return PanelLayoutMetrics.settingsOverrideHeight }
        if showShortcuts  { return PanelLayoutMetrics.shortcutsOverrideHeight }
        return nil
    }

    private var isBugReport: Bool {
        bugReportNoteID != nil && bugReportNoteID == noteStore.currentNote?.id
    }

    // MARK: - Actions

    private func createNote() {
        noteStore.createNote()
        // Signal HeaderView to focus + select the title field
        focusTitleTrigger.toggle()
    }

    private func dismissTransientUI() {
        withAnimation(.easeOut(duration: 0.16)) {
            showAllNotes = false
            showSettings = false
            showShortcuts = false
            showLinkDialog = false
        }
    }

    private func toggleAllNotes() {
        withAnimation(.easeOut(duration: 0.16)) {
            showAllNotes.toggle()
            if showAllNotes { showSettings = false; showShortcuts = false }
        }
        if !showAllNotes { focusEditor() }
    }

    private func toggleSettings() {
        withAnimation(.easeOut(duration: 0.16)) {
            showSettings.toggle()
            if showSettings { showAllNotes = false; showShortcuts = false }
        }
        if !showSettings { focusEditor() }
    }

    private func toggleShortcuts() {
        withAnimation(.easeOut(duration: 0.16)) {
            showShortcuts.toggle()
            if showShortcuts { showAllNotes = false; showSettings = false }
        }
        if !showShortcuts { focusEditor() }
    }

    private func deleteCurrentNote() {
        guard let note = noteStore.currentNote else { return }
        if noteStore.notes.count <= 1 {
            toastState.show("Cannot delete the last note", isError: true)
            return
        }
        noteStore.deleteNote(note)
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
        let tv = tvRef.value
        savedInsertionPoint = tv?.lastKnownCursorPosition ?? NSRange(location: 0, length: 0)
        linkDialogSelectedText = (savedInsertionPoint.length > 0 ? tv.map { ($0.string as NSString).substring(with: savedInsertionPoint) } : nil) ?? ""
        withAnimation { showLinkDialog = true }
    }

    private func copyToClipboard() {
        let text: String
        if let tv = tvRef.value {
            text = tv.plainTextContent()
        } else if let note = noteStore.currentNote,
                  let atStr = try? NSAttributedString(
                    data: note.contentRTF,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil) {
            text = atStr.string
        } else {
            text = ""
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        toastState.show("Copied to clipboard")
    }

    private func cancelBugReport() {
        guard let note = noteStore.currentNote, isBugReport else { return }
        bugReportNoteID = nil
        noteStore.deleteNote(note)
        focusEditor()
    }

    private func createBugReportNote() {
        withAnimation(.easeOut(duration: 0.16)) { showSettings = false }
        noteStore.createNote()
        noteStore.saveTitle("Bug Report")
        bugReportNoteID = noteStore.currentNote?.id
        focusEditor()
    }

    private func sendBugReport() {
        guard let note = noteStore.currentNote, isBugReport else { return }
        let text: String
        if let tv = tvRef.value {
            text = tv.plainTextContent()
        } else if let atStr = try? NSAttributedString(
            data: note.contentRTF,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil) {
            text = atStr.string
        } else {
            text = ""
        }
        bugReportNoteID = nil
        noteStore.deleteNote(note)

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
                toastState.show("Error: \(error)", isError: true)
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
