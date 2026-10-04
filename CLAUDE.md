# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Buoy is a native macOS menu bar sticky-note app — a SwiftUI/AppKit rewrite of a prior Electron version. It lives in the menu bar, shows a floating panel on hotkey, and persists notes as RTF in SQLite.

- **Bundle ID:** `GabeMempin.Buoy`
- **Deployment target:** macOS 15.0 (macOS 26 Liquid Glass conditionals via `#available`)
- **Xcode:** 26.3+, Swift 5.9+, File System Synchronization enabled

## Build & Run

Use the Codex app's **Build & Run** local-environment action or run
`./script/build_and_run.sh` manually. It kills the current Buoy process, builds
the Debug configuration with `xcodebuild`, and opens the resulting app from
DerivedData. In Xcode, opening `Buoy.xcodeproj` and pressing ⌘R remains supported.
Code signing is set to "Sign to Run Locally" — no developer account required.

**Manual verification policy:** Do not run builds, tests, or launch Buoy after
routine code changes unless the user explicitly asks. The user launches the app
manually and reports any failures. Static inspection is the default verification.

**Swift Package dependencies** (managed via Xcode SPM):
- `GRDB.swift` (groue/GRDB) — SQLite ORM
- `KeyboardShortcuts` (sindresorhus/KeyboardShortcuts) — global hotkey registration
- `LaunchAtLogin-Modern` (sindresorhus/LaunchAtLogin-Modern) — login item management

## Architecture

### App Entry & Window Management

`BuoyApp.swift` is the `@main` entry. Almost all app logic lives in **`AppDelegate.swift`** (NSApplicationDelegateAdaptor), which:
- Creates a borderless, always-on-top `NSPanel` (non-activating, transparent)
- Presents Settings as a popover on the footer gear (`SettingsPopover`: General, Appearance, Shortcuts; About is the last section of General) — `openSettings` / `.openSettings` toggle it
- Manages the `NSStatusItem` (menu bar icon) with left/right-click handling
- Owns the `NoteStore` and `AppSettings` instances passed into SwiftUI
- Registers the global hotkey via `HotkeyService`
- Applies themes by setting `NSAppearance` on the panel

### State Management

- **`NoteStore`** (`@Observable`) — single source of truth for notes; loaded from GRDB, with 1s/0.6s debounced auto-save for content/title respectively. Call `flushPendingSaves()` on termination.

**Debounced-save note-identity critical bug pattern (fixed in 1.4.1+):** `saveTitle`/`saveContent` schedule a `DispatchWorkItem` that fires 0.6s/1s later. That work item must bind the **target note's `id` at schedule time** and pass it to `persistTitle(_:noteID:)`/`persistContent(_:noteID:)` — it must NOT read `currentNote` inside the persist body. Reason: `currentNote` can be repointed before the timer fires, so a lazily-resolved persist writes the edit onto the *wrong* note (symptom: a title you typed on Note A "transfers" to a newly-created note, and A reverts to its old title). `switchNote` guards this by calling `flushPendingSaves()` before repointing; **every other path that reassigns `currentNote` must flush first too** — `createNote()` does. Same "capture identity at schedule time, not execution time" trap as the Harbor-mode `lastFullSizeFrame` bug.
- **`AppSettings`** (Codable struct) — persisted to `~/.buoy/settings.json`; `SettingsStore` broadcasts changes immediately and debounces the disk write by 0.25s. Call `settingsStore.flush()` on termination. Add every new field to `AppSettings.init(from:)`, which decodes missing keys using defaults so old files survive upgrades.
- **`Note`** (GRDB record) — stores RTF as `Data` (`contentRTF`), timestamps as `Int64` milliseconds

### Rich Text Editor

**`BuoyTextView`** (NSTextView subclass) is the core editing engine:
- Stores/loads RTF via `NSAttributedString`
- Handles text editing and fixed formatting shortcuts; rebindable app commands are intercepted first by `BuoyPanel.performKeyEquivalent` through `ShortcutRegistry`.
- Auto-converts `- ` + Space → bullet `•`, `[] ` + Space → checkbox attachment
- Bullets and todos continue on Enter; empty list line removes the marker
- `TodoAttachment` is a custom `NSTextAttachment` subclass for checkboxes

**Nested list critical bug pattern:** When removing an empty nested marker at end-of-document, always guard `lineStart < storage.length` before calling `resetParagraphIndent` — otherwise the clamp lands on the previous paragraph's `\n` and strips its indent. After escaping an empty nested line, reset `typingAttributes = normalizedTypingAttributes()` so subsequent typing doesn't inherit the indent.

**`EditorView`** wraps it as `NSViewRepresentable`; **`TextViewCoordinator`** relays delegate callbacks.

### Data Persistence

| Data | Location | Format |
|------|----------|--------|
| Notes | `~/.buoy/notes.db` | GRDB SQLite (RTF binary) |
| Settings | `~/.buoy/settings.json` | JSON (Codable) |
| Pre-migration backups | `~/.buoy/backups/notes-before-<version>-<time>.db` | GRDB online backup, newest 3 kept |

GRDB migrations are defined in `NoteStore.swift` (`v1_initial`, `v2_contentRTF`, `v3_isPinned`, `v4_pinnedOrder`, `v5_autoTitlePending`, `v6_autoTitleStages`, `v7_autoTitleRestage`, `v8_folders`, `v9_noteSortOrder`).

Before `migrator.migrate` runs, `backUpBeforeMigrating` copies the database aside
if it has migrations it hasn't had yet (never on a fresh install). It is silent;
a failed backup or a failed migration posts `.buoyBackupFailed` /
`.buoyMigrationFailed`, shown as toasts 1.5s after launch because the store is
built before any view exists. Migration errors are caught and logged, never
`try?`.

### Key Services

- **`HotkeyService`** — singleton wrapping `KeyboardShortcuts`. Parses Electron-style shortcut strings (`"Option+Cmd+N"`) into `KeyboardShortcuts.Shortcut`.
- **`AppleNotesService`** — writes plain text to a temp file, then runs AppleScript via `osascript` (background queue) to create a new note in Apple Notes.
- **`NoteAutoTitler`** — see "Auto-Title New Notes" below.

### Auto-Title New Notes

On-device naming for new notes via `FoundationModels` (macOS 26, Apple Silicon, Apple Intelligence). `NoteAutoTitler.featureEnabled` is the one kill switch. Rules:

- **Gate every `FoundationModels` symbol** behind `#available(macOS 26, *)` and `#if canImport(FoundationModels)`. Unsupported Macs get no fallback: the Settings toggle shows disabled and off, with `unsupportedReason` underneath; the stored value is untouched.
- **State lives in the DB:** `autoTitleStage` (attempts spent), `autoTitleLocked` (permanent opt-out), `autoTitleDefaultTitle` (the original "Note N"). `saveTitle` (the user typing a title) locks in the same `UPDATE` and calls `cancel(noteID:)`. `evaluate` re-checks the lock and the `stage` before applying, so a stale result is dropped.
- **Thresholds** `[30, 100, 500]` plain-text chars (prewarm at 20). Stage 0 names; later stages refine. `stage == thresholds.count` is done (not locked). **Changing the number of stages needs a paired migration** like `v7_autoTitleRestage`, or finished notes rename themselves again; moving a value within the same count does not.
- **Revert on empty:** an AI-titled note edited back to empty gets `autoTitleDefaultTitle` back and stage 0. Size-gated by `nearEmptyRTFSizeThreshold` so it never decodes RTF per keystroke. Locked notes never revert.
- **Trigger:** `saveContent` → `noteContentDidChange(noteID:)`, a 0.3s debounce that captures the note id at schedule time and never decodes RTF. The 20-char prewarm check lives in `evaluate`.
- **One request at a time, gated on `inFlightRequests`**, never `activeTask != nil`. `respond` ignores cancellation, so a cancelled request still occupies the Neural Engine; freeing the slot on cancel stacked concurrent inferences and bogged the machine down. Completion re-calls `evaluate`.
- **`sanitize(_:)` is the real 3-word/40-char guarantee** (the `@Guide` hint is advisory): trims at word boundaries, drops trailing connectives, returns `nil` rather than a fragment.
- **Warm session:** `warmSessionBox` (`Any?`, since stored properties can't be `@available`) holds one primed session; `generate` consumes it and the completion refills it. Never reuse a session across stages or notes.
- **Failures:** guardrail/context-window errors retry once with a 240-char excerpt; decoding failures retry once greedy; `isRetry` blocks a second retry. Rate-limit/concurrency/assets errors leave the stage unspent. A repeated refusal or unsupported language calls `giveUp` (spend to done, no lock). The failure toast fires only at stage 0.
- **Animations:** `titleReveal` drives `TitleRevealText` (per-glyph reveal over the hidden field text); `titleThinking` drives `TitleThinkingGlow`. Both collapse to crossfades under Reduce Motion.

### All Notes Panel & Folders

The list is an **`NSOutlineView`** (`Views/AllNotesOutline.swift`), not a table.
Three labelled sections: **Pinned** (manual order via `pinnedOrder`),
**Folders** (manual order via `Folder.sortOrder`, children via
`Note.folderOrder`), **All Notes** (manual order via `Note.sortOrder`).

All Notes was chronological-and-fixed at first. That shipped as "reordering
doesn't work": with one pinned note and one folder there was nothing in the
whole list a drag could legally land on. `v9_noteSortOrder` adds the column and
seeds it from `createdAt`, so the order looks unchanged until the first drag.

**Folders group, they do not move.** A note with a `folderID` still appears in
the All Notes section, and a pinned + filed note appears in all three sections
at once. One note belongs to at most one folder. `Folder` rows carry no foreign
key to `notes` on purpose — deleting a folder is one `UPDATE ... SET folderID =
NULL` and never deletes a note.

**One drag source, always.** Every drag starts from
`outlineView(_:pasteboardWriterForItem:)` and nothing else. The previous
implementation had *two* (a custom `NoteRowDragHandle` under the title plus the
table's built-in row drag), so the feel depended on which pixel you grabbed:
one had a 0.16s hold and a card image, the other neither. Do not add a second
drag path. The card image is applied in
`outlineView(_:draggingSession:willBeginAt:forItems:)` via
`enumerateDraggingItems`; the source row dims to 0.28 there and restores in the
`endedAt` callback. Never set `animatesToStartingPositionsOnCancelOrFail =
false` — the slide-back is how a rejected drop tells the user it was rejected.

**Commit with `moveItem`/`insertItems`/`removeItems`, never `reloadData`.**
`acceptDrop` mutates the coordinator's node tree, animates inside
`beginUpdates`/`endUpdates`, *then* writes to the store. The store write
re-renders SwiftUI, which calls `updateNSView` — which compares the rebuilt
tree's `signature` to the one the drop already produced, finds them equal, and
does nothing structural. That is what keeps the old double-snap from coming
back. `reloadData` is the fallback for structural changes nobody animated (new
note, delete, pin toggle, search edit).

**Row content is SwiftUI but not hit-testable.** `PassthroughHostingView`
returns `nil` from `hitTest` except over rects the row published through
`InteractiveRegionKey`, so `mouseDown` reaches the outline view (which owns
selection and drag) while buttons still work. **Every clickable control in a row
must carry `.interactiveRegion(in:)` or it is dead.** Hover is owned by
`NotesRowView`'s tracking area, not SwiftUI's `onHover`, for the same reason —
and that structurally prevents hover state from leaking between rows on cell
reuse.

**Clicks** come from `NotesOutlineView.mouseDown`: it runs `super.mouseDown`
(AppKit's tracking loop, which starts drags) and treats anything that finishes
without a drag session as a click. The delegate sets
`didStartDragDuringTracking`. A click on a folder row toggles its disclosure —
the chevron is a drawn affordance, not a button, so there is no double-fire.

**Row heights are per-item** (`heightOfRowByItem`): note 30, folder 28, header
26. There is no global `rowHeight`. `indentationPerLevel` is 0 and folder
children indent themselves in SwiftUI via `allNotesChildIndent`.

**Sections are labelled, not just ruled.** `AllNotesSectionHeader` draws
PINNED / FOLDERS / ALL NOTES with the hairline above all but the first. Bare
rules said the list was grouped but never why. Headers appear only when there
is more than one section, and a drop on one means the start of the section it
names.

**Row margins: `.plain` style, pill inset drawn in SwiftUI.** The row's text
sits 10pt from the panel edge, level with the section headers, and the fill
behind it stops 4pt short so it never runs into the panel's rounded corner.
`NSTableView.Style.inset` was tried and reverted: its margin *stacks* on the
row's own content padding, which at Buoy's panel width pushed the titles about
twice as far in as the headers. Change the pill inset, not the table style.

**Row action buttons are bare glyphs with a press state.** `RowActionButton` /
`RowActionButtonStyle` in `AllNotesPanel.swift`. A filled chip behind every
resting row action reads heavier than the row itself, and Apple's own lists
don't do it — so the fill is the *press* state instead. The HIG is explicit:
"Always include a press state for a custom button. Without a press state, a
button can feel unresponsive." The 22pt hit region is deliberately larger than
the 10pt glyph. Use this style for any new row control rather than hand-rolling
a button.

**A drop *onto* a row means "put it in that row's slot",** not "insert above
it" — `draggedTopLevelIndex` decides which side. Inserting above is a no-op
when the dragged row is the one directly above the target, which made a
two-item swap look broken.

**Search flattens everything**: sections, folders and all dragging are off while
`searchText` is non-empty (`searchMatches != nil`).

**Keyboard and context menus.** The list never takes focus
(`refusesFirstResponder`); the search field does, on open. ↑/↓ in it move a
highlight (`Coordinator.keyboardKey`, drawn as an accent ring), Return opens
it, Escape clears the search and then closes the panel. While searching, the
first match is highlighted so Return opens it. ⌘⌫ is a rebindable command that
fires before the field sees it, so `ContentView.deleteCurrentNote` asks
`AllNotesKeyboardController.highlightedNote` first. Right-click menus come from
`NotesOutlineView.menu(for:)` → `Coordinator.contextMenu(forRow:)`; row actions
are also VoiceOver named actions on a single `.ignore` element per row, because
the hover buttons only exist while a mouse is over the row.

**Look notes up through `notesByID`, never `notes.first { }`.**
`renderSignature` runs for every row on every update; a linear scan there made
the diff O(rows × notes).

**Panel width** is the window content width minus `overlayHorizontalInset * 2`,
set by `AllNotesOverlay`, not a literal. `AllNotesOverlay` exists because
`ContentView.body` is at the type-checker limit and the panel needs a dozen
closures — keep new All Notes wiring in that file.

### Find in Note (⌘F)

`NoteFindController` + `NoteFindBar` (`Views/NoteFindBar.swift`). The bar
replaces the formatting toolbar while open, so the note never jumps. Matches are
recomputed on every step (never cached) and highlighted with layout-manager
*temporary* attributes, so they are never saved or undone. It closes on a note
switch and in `dismissTransientUI`. `findInNote` is a `BuoyCommand`, so it is
rebindable and routed through `BuoyPanel.performKeyEquivalent` like the others.

### Shortcuts Actions

`Services/BuoyIntents.swift`: Create, Add to, Get Text, Open. `NoteIntentBridge`
is installed by `AppDelegate` at launch; `ContentView` keeps `editor` pointed at
the live editor. **Appending to the open note must go through the editor**
(`appendExternalText`): the editor only reloads on a note switch, and its next
debounced save would overwrite a direct DB write. Other notes are rendered in an
offscreen `BuoyTextView` and written with `NoteStore.replaceContent`, which
flushes pending saves first.

### Bug Report Mode

Clicking "Report a Bug" in the About section of Settings ▸ General, creates an ephemeral note, and sets `bugReportNoteID` in `ContentView`. `isBugReport` is a computed property — navigating away passively exits the mode with no cleanup needed. The `TitleTextField` text color is set to `.clear` so the `AnimatedBugTitle` overlay shows through. Its shimmer comes from `BuoyTheme.bugReportShimmer(isDark:)`: the accent swept by its complementary hue (gold for near-grey accents). The bug-report toolbar and Send Report button use the theme accent, not a fixed blue.

### macOS Version Conditionals

Glass/vibrancy uses `#available(macOS 26, *)`:
- **macOS 26+:** `.glassEffect()` SwiftUI modifier (Liquid Glass)
- **macOS 15:** `NSVisualEffectView` with `.menu` material via `VisualEffectBackground`

The `View+Glass.swift` helper abstracts this behind `.buoyGlass()`.

## Key Files

| File | Purpose |
|------|---------|
| `App/AppDelegate.swift` | Window, menu bar, hotkey, theme management |
| `Models/NoteStore.swift` | @Observable data store + GRDB CRUD |
| `Models/AppSettings.swift` | Settings persistence |
| `Views/Settings/` | Settings popover and its General, Appearance, Shortcuts pages |
| `Helpers/ChromeMetrics.swift` | Continuous regular→compact control sizes; window-size density reader; `HarborTransitionLayout` |
| `Models/HarborTimer.swift` | Harbor Mode countdown: title parsing, per-note timers, completion chime |
| `Helpers/BuoyTheme.swift` | Window tint and app accent, including AppKit bridge |
| `Services/ShortcutRegistry.swift` | Rebindable in-app commands and conflict checks |
| `Editor/BuoyTextView.swift` | Core NSTextView with all formatting logic |
| `Views/ContentView.swift` | Root SwiftUI layout and panel state |
| `Views/OnboardingView.swift` | 4-slide carousel onboarding (Welcome, Formatting, Harbor Mode, Bug Report) |
| `Views/AllNotesOutline.swift` | The All Notes `NSOutlineView`: nodes, drag/drop, passthrough hosting view |
| `Views/Panels/AllNotesPanel.swift` | All Notes chrome + `NoteRow` / `FolderRow` / inline rename |
| `Views/Panels/AllNotesOverlay.swift` | Mounts the panel and binds it to `NoteStore` |
| `Models/Folder.swift` | One-level note folder record |
| `Helpers/WindowDragBlocker.swift` | DragBlockingNSView + ArrowCursorOverlay NSViewRepresentables |
| `Helpers/PanelLayoutMetrics.swift` | All window/panel sizing constants |
| `App/MainMenu.swift` | Whole main menu bar (App/Edit/Format/Window) + `EditMenuDelegate` |
| `Helpers/BuoyMotion.swift` | Reduce Motion gate for every movement animation |
| `Helpers/BuoyAppearance.swift` | `BuoyContrast`, semantic `Color.buoy*` tokens, `BuoyFont` scale |
| `Helpers/NotePlainText.swift` | Memoised RTF→plain-text; use instead of decoding inline |
| `Services/NoteAutoTitler.swift` | On-device AI auto-titling for new notes (FoundationModels, macOS 26+) |
| `Models/WhatsNewCatalog.swift` | Bundled release notes for the post-update splash |
| `Views/WhatsNewView.swift` | The post-update "What's New" splash |

## Developer Workflows

### Reset Onboarding
```bash
sed -i '' 's/"onboarded":true/"onboarded":false/' ~/.buoy/settings.json
```
The phrases **"invoke onboarding"** or **"reset onboarding"** mean run this command.

### Harbor Mode Spam → Square Panel Bug
**Critical bug pattern:** `enterMinimizedMode()` saves `lastFullSizeFrame = p.frame`. If a restore animation is in flight when this fires, `p.frame` is an intermediate size, corrupting the saved frame. Fix: guard the write with `isMinimizeAnimating: Bool` in AppDelegate. Set the flag before `animatePanel()`, clear it after `minimizedFrameAnimationDuration + 0.05s` via `DispatchQueue.main.asyncAfter`. Both `enterMinimizedMode` and `exitMinimizedMode` set the flag.

### Harbor Mode Exit Crash (`_postWindowNeedsUpdateConstraints`)
**Critical bug pattern (fixed in 1.1.3).** `exitMinimizedMode()` ran the SwiftUI pill→editor swap (`withAnimation { panelPresentation.isMinimized = false }`) and the animated `animatePanel(... setFrame(display: true))` in the **same runloop iteration**. Restoring remounts the full `NSTextView` (heavier with `TodoAttachment`s) while AppKit is mid-resize → re-enters the window's constraint pass → `-[NSWindow _postWindowNeedsUpdateConstraints]` assertion kills the app. This was latent for months; a recent macOS point update (Sequoia/macOS 26 line) promoted the re-entrancy from a logged warning to a hard assertion, so it began crashing all users at once. **Fix:** defer the frame animation one runloop tick via `DispatchQueue.main.async`, guarded by `minimizeAnimationGeneration == generation` so spam-toggling can't fire a stale animation. The earlier 1.1.2 fix (`hosting.sizingOptions = []`) only closed the *re-enter* path, not the *exit* path. Rule: never run `setFrame(display: true)` inside (or in the same iteration as) a SwiftUI `withAnimation` transaction that swaps the panel's content.

### Harbor Mode Transition Layout
`enterMinimizedMode`/`exitMinimizedMode` call `holdHarborTransitionLayout` before flipping `isMinimized`: it sets `PanelPresentationModel.harborTransitionGlassSize` (the outgoing size on enter, the target size on exit) and the edge the window keeps still. `HarborTransitionLayout` lays the full panel out once at that size, clipped to the glass's rounded shape, so the window reveals or covers it instead of re-wrapping the editor every frame. It must stay one modifier chain with `nil` meaning unconstrained: an `if let` branch changes the content's identity, which rebuilt the whole panel (editor included) at the start of a fold, leaving an empty glass rectangle for a moment, and again at the end of a restore. `finishMinimizeAnimation` (generation-guarded) clears it, publishes the final window size, and on a restore posts `.buoyHarborRestoreFinished`, which focuses the editor. Never end the transition on an `asyncAfter` in the view: a stale timer from an earlier toggle clears it mid-sweep. The SwiftUI swap and the frame animation share one duration (`minimizedTransitionDuration == minimizedFrameAnimationDuration`) and curve. Entry defers its frame animation one runloop tick, like exit, so the swap's first-frame work doesn't eat the sweep's opening frames; the outgoing panel only fades (the window shrink is the motion), and the corner-resize overlays are hidden up front and not moved per frame during the sweep.

### Harbor Timer
A note whose *whole* title is a duration (`HarborTimer.duration(in:)`: `5m`, `1h30`, `1 hr 30 min`, `half an hour`, `1:30`, optional "timer", …) starts a countdown when it enters Harbor Mode. Timers are per note (`PanelPresentationModel.harborTimers`), in memory only. While one runs, the header shows the countdown as a button that folds the panel into Harbor Mode, where pause/stop live. At "Time's up" the header gives the title back for editing; renaming the note stops the finished timer. `updateRemaining` ticks at 0.2s but only publishes when the displayed second changes.

### Off-Screen Drag / Harbor Pill Position
**Bug pattern (fixed in 1.1.3).** `DragEnablingNSView.mouseDragged` (in `WindowDragBlocker.swift`) called `window.setFrameOrigin(...)` with no clamping, so the header could drag the panel up under the menu bar / off any edge into an unreachable spot. The Harbor pill frames (`topCenteredFrame`/`bottomCenteredFrame`) in `enterMinimizedMode`/`updateMinimizedWidth` were likewise unclamped. **Fix:** clamp the dragged origin to `(window.screen ?? NSScreen.main).visibleFrame`, and wrap the pill anchored frames in `clampedToVisibleFrame(...)`. Not OS-dependent — purely a missing clamp.

### NSTextView Cursor Bleed into Overlay Panels
**Fixed.** `BuoyTextView` registers an I-beam `NSTrackingArea` that used to bleed through SwiftUI overlays (All Notes, Update Bubble, onboarding). A view-based overlay (`ArrowCursorOverlay`) could not intercept it because AppKit dispatches `cursorUpdate` to the deepest hit-testable view. `BuoyTextView.suppressesIBeamCursor` now skips `super` while an in-panel overlay is up. `ContentView` updates the flag and re-syncs it in the `textViewRef` callback for the initial onboarding case. The Settings window is independent and does not suppress the panel's cursor. Clickable controls in panel overlays use `pointingHandCursor()` from `WindowDragBlocker.swift`.

### Focus Fog (shake the header)
Shaking the header's control row (`WindowDragHandle(onShake:)`, detected by `ShakeDetector` in `WindowDragBlocker.swift`) posts `.buoyToggleFocusFog`; `AppDelegate.toggleFocusFog` runs `FocusFogController`, which covers every screen with a mouse-blocking window showing a heavily blurred copy of *that screen's* wallpaper. Rules:
- **Render ahead, never on shake.** `prepare()` runs at launch, after every hide, and on Space changes; it decodes a ≤960px thumbnail off the main thread and caches by `WallpaperKey` (URL + frame index). Decoding the full 6K HEIC on demand was the "lag before the fade". Fade in is ease-*out*: ease-in-out also read as a delay.
- **Wallpaper kinds:** stills and Apple's solid colours (PNGs) via ImageIO; dynamic HEICs pick the current frame from the XMP plist (`h24` by time of day, `solar`/`apr` by light/dark `ap`); video (Aerial) wallpapers via the first `AVAssetImageGenerator` frame. Anything unreadable falls back to a live `NSVisualEffectView` blur.
- **The fog sits at `.floating - 1` and must stay under the panel.** `panelWindowLevel` lifts the panel to at least `.floating` while the fog is up, then restores it; any new code that sets `panel.level` must go through it. Re-sync the corner overlays (`syncWindowProperties`) after a change.
- **One toggle per drag gesture** (`didShake`), or continued shaking flips it straight back. Detection reads screen coordinates, since the window follows the pointer.
- **The fog blocks the mouse.** Each screen gets a `FogPanel` (`.nonactivatingPanel`, never key or main) with `ignoresMouseEvents = false`, and `FogView` swallows clicks and scrolls, so nothing behind it can be clicked. Clicks on it don't resign the panel, because `isInsideAttachedWindow` counts any visible Buoy window. The menu bar and Dock sit above `.floating - 1` and stay usable. `hidePanel` drops the fog instantly.
- **Never fade the fog to alpha 1** (`shownAlpha` is 0.99). Fully opaque, it occludes the whole desktop, macOS drops the wallpaper underneath, and the first fade out showed black until it redrew.
- **First-use tip:** `AppDelegate` posts `.buoyFocusFogDidShow`; `ContentView`'s router shows "Shake the window to exit Fog Mode" for 5s once, gated on `hasSeenFocusFogTip`.
- **Two styles** (`AppSettings.focusFogStyle`, picked in Settings ▸ Appearance ▸ Fog Mode): `.wallpaperBlur` and `.gradient`. `prepare()` renders both from one decode into `FogAssets` (blur + 9-colour palette). `FogPalette` k-means the wallpaper into 5 colours and boosts saturation and contrast; when the main colours sit close together (spread < 0.15) it uses shades of the dominant colour instead, so a black wallpaper gives black and greys. An unreadable wallpaper's gradient comes from its fill colour. The gradient is two still 3×3 `MeshGradient` images (`FogMeshImage`, rendered once with `ImageRenderer`) on square layers as wide as the screen diagonal, turning in opposite directions via `CABasicAnimation`, with the top one breathing in opacity. **Keep the motion in Core Animation:** a SwiftUI `TimelineView` in the fog window rendered once and never moved. Animations stop on hide (`stopAnimating`) and are skipped under Reduce Motion. `setStyle` restyles a fog that is already up.
- **No tint, veil or mist over the blur.** A white veil and drifting mist were tried and removed: they read as a white wash instead of the user's wallpaper.

### Shift + Scroll Note Navigation
`DragBlockingScrollView.scrollWheel` (`Editor/EditorView.swift`) handles the horizontal two-finger swipe and Shift + scroll. Rules:
- **Gate on the modifier, not the device.** macOS only moves Shift + scroll onto the X axis for a plain wheel; trackpads and Magic Mice keep reporting Y, so a device check made the gesture unreachable for most users. `isNavigationModifier(_:)` requires Shift without Cmd/Option/Control and ignores Caps Lock.
- **Pick the axis by magnitude, never by `!= 0`**: a vertical swipe always carries some X jitter.
- **Precise devices:** `navigateByPreciseScroll` latches `hasNavigatedInCurrentGesture` and clears it at `.ended`/`.cancelled`, so one swipe moves exactly one note. **Plain wheels** have no phase: `navigateByWheel` rate-limits with a cooldown plus idle reset (~one note per 0.35s).
- **Drop momentum events** (`event.momentumPhase == []`).
- **Positive delta means previous**, matching the swipe; follow the system's natural-scrolling direction, don't normalise it.
- Shift events are always consumed (never passed to `super`), so the editor doesn't also scroll.

### Carousel Onboarding
`OnboardingView.swift` — 4 slides: Welcome (key caps + global shortcut recorder), Formatting (live BuoyTextView demo), Harbor Mode (the current Harbor shortcut animates a mini panel to pill), Bug Report (shimmer title via `AnimatedBugTitle`). A local `NSEvent` monitor captures the registry's Harbor combo during onboarding — on slide 3 it toggles the demo, on all other slides it consumes the event. `AnimatedBugTitle` in `HeaderView.swift` is `internal` so it can be reused in Slide 4. `hasSeenHarborModeTip` remains for backwards compatibility but is never set.

### Scrolling Note Titles
`Views/MarqueeText.swift` is shared by the Harbor pill (`MinimizedNotePillView`)
and the main header (`HeaderView`) — both render the same title in
`PanelLayoutMetrics.minimizedTitleFont`, so they measure against one font and one
set of `marquee*` timing constants. It scrolls only when the text overflows its
lane, and renders static truncated text under Reduce Motion.

Scroll phase is shared through `MarqueeClock`, keyed on the text. The header and
the pill are separate views, so without it, morphing into Harbor Mode mid-scroll
would snap the title back and re-run the opening pause. Entries linger 1s after
`onDisappear` — long enough to cover the ~0.26s morph, short enough that
returning to a note later starts cleanly from the pause. A title *change* calls
`restart` instead, since there's no phase worth keeping.

In the header it is an *overlay*: the real `NSTextField` stays in place for
editing, and `hidesText` blanks its glyphs while the marquee stands in — the same
trick Bug Report mode uses for `AnimatedBugTitle`. The overlay is suppressed while
`isEditingTitle` (driven by `controlTextDidBeginEditing`/`DidEndEditing`), because
text sliding out from under the caret is unusable. `TitleTextField.textColor(for:)`
is the single source for the colour so the field and the overlay can't drift.

### Settings Popover, Colours, Compact Chrome, and Shortcuts

Settings is a SwiftUI `.popover` on the footer gear (`SettingsPopover`), not a window. It points at its button, moves with the panel and closes on a click away for free. `AppDelegate.isInsideAttachedWindow` keeps a click inside any popover from counting as an outside click (which used to resign the panel and close the popover before the control saw the click). The popover window only mirrors the panel's key state, so `NSApp.keyWindow` stays the panel and `BuoyPanel.performKeyEquivalent` still receives rebindable shortcuts while it is open (verified).

`ChromeMetrics(compactness:)` interpolates every chrome size continuously between regular (0) and compact (1). `ChromeDensityReader` derives compactness from `PanelPresentationModel.windowSize` (published by `AppDelegate`) — there is no toggle and no threshold. The reader takes the presentation model and reads the size itself, so a resize re-renders only the reader, not `ContentView.body`. Editor text scales through scroll-view magnification, never `settings.fontSize`. The reader is suspended while minimized and during the Harbor sweep (`harborTransitionGlassSize != nil`).

`BuoyTheme` resolves the optional window tint and accent. SwiftUI surfaces read the environment; AppKit selection, checkbox images, list reorder indicator, title field, and corner arcs read `BuoyTheme.current`. A checked `TodoAttachment` bakes its accent into an image, so `BuoyTextView` refreshes existing attachments on `.buoyThemeDidChange`. Derive text on a custom accent from that accent's luminance; `alternateSelectedControlTextColor` only knows the system accent.

`ShortcutRegistry` owns the rebindable app commands. `BuoyPanel.performKeyEquivalent` dispatches them before the responder chain, so a binding works with the editor or title focused. Keep fixed formatting and standard text editing keys in `BuoyTextView`. `ShortcutsSettingsPage` records physical key codes through `KeyCombo`, rejects conflicts with another command, the global hotkey, or fixed/system keys, and resets only the overrides. Rebuild the main menu when a binding changes; the status item menu reads the registry each time it opens. Do not add a second hard-coded match in `BuoyTextView` or a stale literal shortcut hint in a button.

### Accessibility & Menu Conventions
Added in the HIG pass (2026-08-22):
- **Reduce Motion:** never write a bare `withAnimation(.spring/.easeOut/...)` for
  anything that *moves or scales*. Route it through `BuoyMotion.spring/easeOut/…`,
  transitions through `BuoyMotion.transition(_:)`, and AppKit frame animations
  through `BuoyMotion.duration(_:)`. `AppDelegate.animatePanel` is already gated,
  so every panel frame animation inherits it. Pure opacity fades are left alone —
  Reduce Motion is not an animation kill switch. Continuously-rendering SwiftUI
  views (Harbor pill marquee, `AnimatedBugTitle`) use
  `@Environment(\.accessibilityReduceMotion)` instead, so they react live.
- **Reduce Transparency:** all four glass entry points (`buoyGlass`,
  `buoyInsetGlass`, `buoyGlassPanel`, `buoyGlassCapsule`) branch on
  `@Environment(\.accessibilityReduceTransparency)` **first**, falling back to
  `BuoyOpaqueSurfaceBackground` (flat `windowBackgroundColor`/`controlBackgroundColor`
  + full-strength `separatorColor` border). With the setting off, the glass paths
  are unchanged — never make the opaque surface unconditional. A new glass
  surface must add the same leading branch or it will stay translucent.
- **Colors:** use the `Color.buoy*` tokens in `BuoyAppearance.swift` rather than
  `Color.primary.opacity(0.08)`-style literals — they boost themselves under
  Increase Contrast. `Color.buoyOnAccent` replaces literal `.white` on any
  accent-filled control. Known limitation: the tokens read `NSWorkspace` at body
  evaluation, so toggling Increase Contrast mid-session applies on the next
  re-render rather than instantly.
- **Type:** chrome text uses the `BuoyFont` roles (they resolve to the macOS text
  styles that already render at Buoy's sizes). SF Symbol sizing stays as explicit
  `.system(size:)` — those are icon metrics, not type.
- **Every clickable control needs `.accessibilityLabel`.** Icon-only buttons reach
  VoiceOver unnamed otherwise. Tooltips are not labels: `ToolbarPillButton` takes
  `label` and `shortcut` separately so the spoken name isn't "Bold (⌘B)".
- **No focus rings, by design.** Both the title and All Notes search fields set
  `focusRingType = .none` and draw no substitute. AppKit's ring masks to the
  *cell frame*, so on a borderless field it lands as a hard-edged box — on the
  full-width title field, a box around mostly empty space. A tighter ring and a
  2pt underline were both tried and rejected as clutter. The insertion caret
  marks focus for sighted keyboard users and the accessibility labels carry it
  for VoiceOver, so don't reintroduce a drawn indicator without asking.
  Two gotchas if you ever do: `.default` on a borderless field gives no sensible
  shape, and `NSTextField` is flipped so its visual bottom is `maxY`.
- **No AppKit find bar.** `usesFindBar` was tried and reverted: the find bar's
  intrinsic minimum width (search field + prev/next + Done) exceeds Buoy's 292pt
  `minimumContentWidth`, so it cannot compress — it overflows the scroll view and,
  since the editor is not clipped to the glass shape, paints *outside* the window
  while the panel is resized. A find feature here has to be built to Buoy's own
  chrome.
- **Menus need Dock mode.** With "Show in Dock" off, Buoy is `.accessory` and has
  no menu bar at all, so `NSApp.mainMenu` is never displayed. The status item's
  right-click menu (`AppDelegate.showContextMenu`) is the always-available
  surface — put app-level commands in both.
- **`ContentView.body` is at the type-checker limit.** Adding even one
  `.onReceive` tipped it into "unable to type-check in reasonable time". Simple
  notification handlers go in `BuoyNotificationRouter`'s dictionary (one merged
  publisher, one modifier), not as new modifiers on the chain.
- **Non-activating panel caveat:** `NSApp.mainMenu` key equivalents do *not*
  reliably fire, because the panel is a `.nonactivatingPanel` and the app usually
  runs `.accessory`. Any new menu shortcut must also be routed in
  `BuoyPanel.performKeyEquivalent` (see the selector table and
  `performTextFinderAction(_:on:)` there) or it will be dead outside Dock mode.
- **Never decode RTF in a view body.** Use `NotePlainText.of(note)` — it memoises
  on `id` + `updatedAt`. Two call sites were decoding on paths that run
  constantly: the footer's word/character readout re-decoded the current note on
  every `ContentView.body` evaluation, and All Notes' search re-decoded *every*
  note on every keystroke.
- **Placeholder text must be opaque.** The editor sits on glass, so any
  `foregroundColor` below 100% alpha lets the desktop show *through the
  letterforms* and the text dissolves into the backdrop. `editorPlaceholderColor`
  is a solid grey at alpha 1 — "faded" comes from the colour, never from alpha.
  `placeholderTextColor`/`secondaryLabelColor` both fail here. A halo shadow was
  tried and reverted: at any blur wide enough to separate 13pt glyphs from the
  backdrop it also bleeds over them and washes the text out.
- **Ephemeral notes use `createNote(titled:)` + `discardNote(_:)`.** The Bug
  Report note is a real DB row. Titling it at insert avoids a debounced write
  landing on a row that is about to be deleted, and keeps it from consuming a
  number in the "Note N" sequence. `discardNote` skips `deleteNote`'s
  "keep at least one note" guard, which otherwise strands a permanent note
  titled "Bug Report" when it is the only note.
- **Text checking:** `BuoyTextView` remounts on every note switch, so the Edit ▸
  Spelling/Substitutions toggles persist through `BuoyTextView.TextCheckingOption`
  (UserDefaults) and replay in `commonInit`. Add new toggles there, not as bare
  property assignments.

### .gitignore Notes
Build artifacts (`*.app/`, `*.zip`, `build.log`, `Buoy */`), VS Code config, and AGENTS.md are gitignored. CLAUDE.md is tracked. Never commit compiled app bundles or build logs.

### Co-Authored-By Attribution
Never add `Co-Authored-By` lines to commits. The git user.name was previously corrupted to `"user.email"` via a bad local config — fixed by removing the local override with `git config --local --unset user.name`.

### What's New Splash

Shown once on the first launch after Buoy updates to a version that has notes.
iOS-style: app icon, title, version, rows of SF Symbol + heading + one-line
description under "What's New" and "Bug Fixes", Continue pinned at the bottom.

- **Content is bundled**, not fetched: `Models/WhatsNewCatalog.swift` holds one
  `WhatsNewRelease` per version. **The entry must be written before
  `xcodebuild archive`** — it is compiled into the app. `/newupdate` Step 1.5
  (the approval gate, moved ahead of the archive) and Step 1.6 do this.
- **`WhatsNewRelease.version` must equal `MARKETING_VERSION` exactly.** A
  mismatch is silent: the lookup finds nothing and no splash appears. That is
  also the deliberate behaviour for a release with nothing worth announcing —
  omit the entry and `lastSeenWhatsNewVersion` is left untouched.
- **Gating:** `WhatsNewCatalog.shouldPresent` requires `onboarded`, so a fresh
  install gets the carousel instead. `OnboardingView.complete()` stamps
  `lastSeenWhatsNewVersion` alongside `onboarded = true`, or a new user would
  see the splash on their second launch.
- **The version is written on Continue, not on show**, so quitting without
  acknowledging brings the splash back next launch. That is intended, not a bug.
- **The editor is live underneath.** The splash is opaque but the real note is
  still mounted, so `WhatsNewView` installs a local key monitor that swallows
  bare typing (chords with ⌘/⌃/⌥ pass through for ⌘Q, ⌘W and VoiceOver), and
  `ContentView` guards `createNote`, `navigateNote`, `deleteCurrentNote`,
  `toggleAllNotes` and `presentLinkDialog`
  with `!showWhatsNew`. ⌘⌫ matters most: `deleteConfirmOverlay` is an `.overlay`
  on `fullPanelContent`, so it would render *above* the splash.
- **The current Harbor shortcut is swallowed too**, because Harbor Mode unmounts the splash and restores
  at compact height, clipping it. The Dock-mode Window menu item bypasses that
  monitor, so `dismissTransientUI` calls `dismissWhatsNew()` as the fallback.
- **The panel launches pre-sized** (`AppDelegate.setupPanel`), the way onboarding
  does, so it does not visibly stretch a beat after launch. That requires setting
  `overlayOverrideHeight` up front while leaving `currentHeight` at
  `compactHeight` — if `currentHeight` absorbs the tall height, the panel never
  shrinks back after Continue.

Reset it (the phrase **"reset what's new"** means run this):
```bash
sed -i '' 's/"lastSeenWhatsNewVersion":"[^"]*"/"lastSeenWhatsNewVersion":null/' ~/.buoy/settings.json
```

### Overlay Panel Height Override
Onboarding and the What's New splash animate the panel taller when shown. Settings is a popover and never resizes the panel. Key pieces:
- `PanelLayoutMetrics.onboardingOverrideHeight` / `whatsNewOverrideHeight` — target heights
- `AppDelegate.applyOverrideHeight(_ height: CGFloat?)` — pass `nil` to restore; 0.25s easeInEaseOut
- `ContentView` fires `onOverrideHeight` via `.onChange(of: activeFooterOverlayHeight)` and directly in `onAppear` for whichever overlay is already up at first render
- Panel bottom offset from footer: `.padding(.bottom, 43)` in `ContentView`
