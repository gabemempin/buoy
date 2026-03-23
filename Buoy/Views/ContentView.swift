import SwiftUI
import AppKit
import Sparkle

/// Stable reference holder for the NSTextView. Using a class (@StateObject) instead of
/// @State ensures the reference survives all SwiftUI re-renders and is safe to mutate
/// from within makeNSView/updateNSView without triggering re-render loops.
private final class TextViewRef {
    var value: BuoyTextView?
}

struct ContentView: View {
    var noteStore: NoteStore
    @Binding var settings: AppSettings
    var updaterController: SPUStandardUpdaterController?
    var onHeightChange: ((CGFloat) -> Void)?
    var onClose: () -> Void
    var onMinimize: () -> Void
    var onExpand: () -> Void

    // Panel visibility
    @State private var showAllNotes = false
    @State private var showSettings = false
    @State private var showShortcuts = false

    // Link dialog
    @State private var showLinkDialog = false
    @State private var linkDialogSelectedText = ""

    // Toast
    @State private var toastState = ToastState()

    // Text view reference for toolbar actions — @StateObject persists across all re-renders
    @State private var tvRef = TextViewRef()

    // Title focus trigger
    @State private var focusTitleTrigger = false

    // Cursor position captured before link dialog opens (avoids stale selection overwriting it)
    @State private var savedInsertionPoint: NSRange = NSRange(location: 0, length: 0)

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main layout
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
                    dragEnabled: !showSettings && !showShortcuts && !showAllNotes
                )

                ToolbarView(
                    onBold:      { applyEditorFormat { $0.applyBold() } },
                    onItalic:    { applyEditorFormat { $0.applyItalic() } },
                    onUnderline: { applyEditorFormat { $0.applyUnderline() } },
                    onBullet: {
                        guard let tv = tvRef.value else { return }
                        let pos = tv.lastKnownCursorPosition
                        tv.window?.makeFirstResponder(tv)
                        DispatchQueue.main.async { tv.applyBullet(pos) }
                    },
                    onTodo: {
                        guard let tv = tvRef.value else { return }
                        let pos = tv.lastKnownCursorPosition
                        tv.window?.makeFirstResponder(tv)
                        DispatchQueue.main.async { tv.applyTodo(pos) }
                    },
                    onLink:      { showLinkDialogFromToolbar() }
                )

                // Inline link dialog
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

                // Editor
                if let note = noteStore.currentNote {
                    EditorView(
                        rtfData: note.contentRTF,
                        fontSize: settings.fontSize.pointSize,
                        noteID: note.id,
                        onHeightChange: { h in
                            DispatchQueue.main.async {
                                onHeightChange?(h + 160)
                            }
                        },
                        onContentChange: { rtf in
                            noteStore.saveContent(rtf)
                        },
                        textViewRef: { tv in
                            tvRef.value = tv
                        }
                    )
                    .frame(minHeight: 200)
                }

                FooterView(
                    createdAt: noteStore.currentNote?.createdAt ?? 0,
                    updatedAt: noteStore.currentNote?.updatedAt ?? 0,
                    onShortcuts: toggleShortcuts,
                    onSettings:  toggleSettings,
                    onTransferToAppleNotes: transferToAppleNotes,
                    onCopy: copyToClipboard
                )
            }

            // Toast overlay
            ToastContainer(state: toastState)

            // Dismiss overlay — tapping outside a panel closes it
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

            // All Notes panel — top-right
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
                    .padding(.top, 36)
                    .padding(.trailing, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .animation(.easeOut(duration: 0.16), value: showAllNotes)
            .allowsHitTesting(showAllNotes)

            // Settings / Shortcuts panels — bottom-left
            ZStack(alignment: .bottomLeading) {
                if showSettings {
                    SettingsPanel(
                        isShowing: $showSettings,
                        settings: $settings,
                        updaterController: updaterController,
                        onQuit: { NSApp.terminate(nil) },
                        onShortcutChanged: { s in HotkeyService.shared.register(shortcut: s) }
                    )
                    .padding(.bottom, 52)
                    .padding(.leading, 8)
                    .onDisappear { focusEditor() }
                }
                if showShortcuts {
                    ShortcutsPanel(
                        isShowing: $showShortcuts,
                        globalShortcut: electronToSymbols(settings.globalShortcut)
                    )
                    .padding(.bottom, 52)
                    .padding(.leading, 8)
                    .onDisappear { focusEditor() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .animation(.easeOut(duration: 0.16), value: showSettings)
            .animation(.easeOut(duration: 0.16), value: showShortcuts)
            .allowsHitTesting(showSettings || showShortcuts)

            // Onboarding overlay
            if !settings.onboarded {
                OnboardingView(
                    settings: $settings,
                    onShortcutChanged: { s in HotkeyService.shared.register(shortcut: s) }
                )
            }
        }
        .padding(6)
        .frame(minWidth: 380)
        .background(WindowDragBlocker())
        .buoyGlass()
        // App-level shortcut notifications from BuoyTextView
        .onReceive(NotificationCenter.default.publisher(for: .buoyNewNote))         { _ in createNote() }
        .onReceive(NotificationCenter.default.publisher(for: .buoyDeleteNote))      { _ in deleteCurrentNote() }
        .onReceive(NotificationCenter.default.publisher(for: .buoyCopyToClipboard)) { _ in copyToClipboard() }
        .onReceive(NotificationCenter.default.publisher(for: .buoyPreviousNote))    { _ in noteStore.previousNote(); focusEditor() }
        .onReceive(NotificationCenter.default.publisher(for: .buoyNextNote))        { _ in noteStore.nextNote(); focusEditor() }
        .onReceive(NotificationCenter.default.publisher(for: .showLinkDialog)) { notif in
            linkDialogSelectedText = notif.object as? String ?? ""
            withAnimation { showLinkDialog = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            withAnimation(.easeOut(duration: 0.16)) { showSettings = true }
        }
        // Block window dragging whenever any overlay panel is open
        .onChange(of: showSettings || showShortcuts || showAllNotes) { _, panelOpen in
            NSApp.windows.compactMap { $0 as? NSPanel }.forEach {
                $0.isMovable = !panelOpen
            }
        }
        // Re-measure height when font size changes
        .onChange(of: settings.fontSize) { _, _ in
            if let tv = tvRef.value {
                let h = tv.measureContentHeight()
                onHeightChange?(h + 160)
            }
        }
    }

    // MARK: - Bindings

    private var titleBinding: Binding<String> {
        Binding(
            get: { noteStore.currentNote?.title ?? "" },
            set: { noteStore.saveTitle($0) }
        )
    }

    // MARK: - Actions

    private func createNote() {
        noteStore.createNote()
        // Signal HeaderView to focus + select the title field
        focusTitleTrigger.toggle()
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
        // Ensure the text view is first responder, then restore selection and apply formatting.
        // Using async so makeFirstResponder + becomeFirstResponder fully complete first.
        tv.window?.makeFirstResponder(tv)
        DispatchQueue.main.async {
            if tv.lastKnownSelection.length > 0 {
                tv.setSelectedRange(tv.lastKnownSelection)
            }
            action(tv)
        }
    }

    private func showLinkDialogFromToolbar() {
        let tv = tvRef.value
        // Capture cursor/selection now — before the dialog opens and takes focus
        savedInsertionPoint = tv?.lastKnownCursorPosition ?? NSRange(location: 0, length: 0)
        let pos = savedInsertionPoint
        linkDialogSelectedText = (pos.length > 0 ? tv.map { ($0.string as NSString).substring(with: pos) } : nil) ?? ""
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
