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
- Owns a separate, titled `SettingsWindowController` with General, Appearance, Shortcuts, and About pages
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

GRDB migrations are defined in `NoteStore.swift` (`v1_initial`, `v2_contentRTF`, `v3_isPinned`, `v4_pinnedOrder`, `v5_autoTitlePending`, `v6_autoTitleStages`, `v7_autoTitleRestage`, `v8_folders`, `v9_noteSortOrder`).

### Key Services

- **`HotkeyService`** — singleton wrapping `KeyboardShortcuts`. Parses Electron-style shortcut strings (`"Option+Cmd+N"`) into `KeyboardShortcuts.Shortcut`.
- **`AppleNotesService`** — writes plain text to a temp file, then runs AppleScript via `osascript` (background queue) to create a new note in Apple Notes.
- **`NoteAutoTitler`** — see "Auto-Title New Notes" below.

### Auto-Title New Notes

**Now live.** `NoteAutoTitler.featureEnabled` is `true`, so `isSupported`
answers on real capability again (macOS 26 + Apple Silicon + Apple Intelligence)
and the Settings row and the `NoteStore`
call-in are all back. It shipped inert for one release because it shares commit
`c651597` (and three source files) with the link popover, so there was no clean
commit to omit; flipping this one constant is the whole switch in either
direction. The migrations stay in either way — additive, harmless while off, and
they keep the schema identical across both builds.

On-device AI naming for brand-new notes, via Apple's `FoundationModels`
framework (macOS 26+, Apple Silicon, Apple Intelligence on). Everything that
touches `FoundationModels` symbols in `NoteAutoTitler.swift` is gated behind
`#available(macOS 26, *)` and `#if canImport(FoundationModels)`; on any
unsupported Mac `NoteAutoTitler.isSupported` is `false` and the whole feature
is inert — no fallback keyword generator, no partial UI. `GeneralSettingsPage`
checks `isSupported` so the toggle row is absent on unsupported Macs.

**Two-stage state machine, tracked in the DB.** `Note.autoTitleStage` (0/1/2)
counts attempts spent; `Note.autoTitleLocked` (default `true`) permanently
opts a note out; `Note.autoTitleDefaultTitle` remembers the original
"Note N" (migration `v6_autoTitleStages` — `createNote(titled:)` sets all
three; pre-v6 rows migrate `autoTitleLocked = NOT` their old `autoTitlePending`,
so a note that was still mid-flight under the old single-shot model keeps
going under the new one). `saveTitle` — the user typing a real title — sets
`autoTitleLocked = true` in the same `UPDATE` as the title write and calls
`NoteAutoTitler.cancel(noteID:)`; a locked note is never touched again.
`NoteAutoTitler.evaluate` re-checks `!autoTitleLocked` before every request,
so a lock that lands mid-flight (or a stage that's since moved on — the
`stage` parameter threaded through `applyAutoTitle`/`spendAutoTitleStage`)
drops a stale result instead of misapplying it.

**Thresholds:** `NoteAutoTitler.thresholds` (`[50, 100, 500]` plain-text
characters) is the source of truth. Stage 0 names the note; every later stage
is a refinement — the prompt shows the model the current title and lets it
keep it. Past the last threshold the note is done: `autoTitleStage ==
thresholds.count` blocks further runs without locking the note. **Editing
this array needs a paired migration**, because it redefines "done" for rows
already in the DB — a note finished under the old array reads as eligible
again under a longer one and renames itself on the next keystroke. That is
what `v7_autoTitleRestage` does for the `[50, 300]` → `[50, 100, 500]`
change (old stage ≥ 2 → 3); follow the same pattern for any future change.

**Revert on empty:** `NoteStore.saveContent` restores `autoTitleDefaultTitle`
and resets `autoTitleStage` to 0 when a note whose title was AI-applied
(`autoTitleStage > 0`) is edited back down to empty text — the size-gated
plain-text check (`nearEmptyRTFSizeThreshold`) keeps this from decoding RTF
on every keystroke of a note that already has substance; it only fires near
the empty boundary. Reverting re-arms stage 0, so typing again re-triggers at
50 chars. A locked (hand-titled) note is never reverted.

**Trigger path:** `NoteStore.saveContent` calls
`NoteAutoTitler.noteContentDidChange(noteID:)` on every keystroke while the
note is unlocked, `AppSettings.autoTitleEnabled` is on, and content isn't
empty. That method is cheap — it just resets a 0.3s coalescing debounce keyed
by note id (same "capture the target id at schedule time" rule as
`saveTitle`/`saveContent` above — see the debounced-save bug pattern). It does
**not** decode RTF: the plain-text length check that arms the model prewarm
(20 characters) lives in `evaluate` instead, since `evaluate` already pays for
`NotePlainText.of(note)` — doing it per keystroke was a guaranteed cache miss
(`saveContent` bumps `updatedAt` before the check could run) and a full RTF
decode on every keystroke of an unlocked note. When the debounce fires,
`evaluate` checks the current stage's threshold and runs one
`LanguageModelSession` request with `@Generable`/`@Guide` guided generation.
Only one request runs at a time, gated on `inFlightRequests` — a count of
`respond` calls actually executing, **not** `activeTask != nil`. `Task.cancel()`
is cooperative and `respond` never checks it, so a cancelled request keeps
occupying the Neural Engine until it finishes; `cancel(noteID:)` clears the
shimmer and drops the stale result but must not free the slot. Gating on
`activeTask` instead meant every cancellation (note switch, `createNote`,
hand-typed title) started another concurrent inference, and since each one also
runs a second safety-model pass, rapidly creating notes could stack up enough
of them to bog down the whole machine. A request's completion re-calls
`evaluate` so a note that crossed the next threshold mid-request doesn't wait
for another keystroke, and a superseded request that finishes last re-evaluates
the note on screen so nothing is stranded behind it. The `@Guide` word-count hint on the model output is
advisory only — the real "3 words max" guarantee is
`NoteAutoTitler.sanitize(_:)`, which trims punctuation/quotes, then trims at
*word* boundaries (drops trailing connective words like "for"/"the", removes
whole words rather than cutting mid-word to fit 40 characters) and returns
`nil` — routing to the same failure path as a refusal — rather than handing
back a truncated fragment.

**Warm session handoff:** one instruction-primed `LanguageModelSession` is
kept ready in `warmSessionBox` (type-erased to `Any?` — a stored property
can't be marked `@available`, so only the code that casts it back needs the
macOS 26 check). `ensureWarmSession()` fills it once the note crosses the
prewarm character count; `generate` consumes and clears it (falling back to
building a session on the spot if none is warm) so a note titled long after
the last one still avoids paying model load on the request the user is
watching; the completion `defer` calls `ensureWarmSession()` again if the note
is still unlocked and has a stage left, so the *next* request's load happens
during typing. Never reuse one session across stages or notes — see the
comment at the handoff site in `generate` for why (transcript anchoring,
cross-note contamination, a cancelled-but-still-running `respond` throwing
`concurrentRequests` on the next call to the same session).

**Failure handling:** `generate`'s `catch` matches on
`LanguageModelSession.GenerationError` and treats failures differently by
cause, with a `default:` arm for any case not listed (behaves like a plain
spend, same as before this was added). `guardrailViolation` and
`exceededContextWindowSize` retry once with a 240-character excerpt;
`decodingFailure` retries once with greedy sampling; either retrying twice
would spin the model on content it will never accept. A retry re-enters
`generate` for the same `expectedStage`/`nextStage`, which bumps `generation`
again so `cancel()` still fences it, and `isRetry` blocks a second attempt.
`rateLimited`, `concurrentRequests`, and `assetsUnavailable` are transient —
the stage is left unspent and only `titleThinking` is cleared; the next
keystroke re-arms through the debounce rather than retrying immediately (a
cancelled `respond` keeps running server-side, so retrying now would likely
queue behind it). A repeated guardrail refusal or `unsupportedLanguageOrLocale`
calls `giveUp`, which spends straight to `thresholds.count` (finished, same
value normal completion and `v7_autoTitleRestage` use) without locking the
note — revert-on-empty still works if the text is cleared later. The failure
toast (`.buoyAutoTitleFailed` / `.buoyAutoTitleUnsupportedLanguage`, the
latter for the give-up-on-language case, routed in `ContentView`'s
`BuoyNotificationRouter` dictionary since its closures take no argument) only
fires when `expectedStage == 0` — a failed *refinement* is invisible, since
the note already has a title and toasting would just repeat what the user can
already see.

**Reveal + thinking animations:** `NoteStore.applyAutoTitle` sets
`titleReveal: TitleReveal?` (noteID + title) the instant a title lands, and
the title field's binding already has the new string — only the *glyphs* are
hidden. `HeaderView`'s `TitleRevealText` (same `hidesText`-on-`TitleTextField`
trick as the shimmer and the marquee) stripes in each character left-to-right
(0.18s per character, 20ms stagger), then calls back to clear
`noteStore.titleReveal`. While a request is running, `noteStore.titleThinking`
(the note id) drives `ShimmerTitle` — the sweep `AnimatedBugTitle` used to own
outright, now extracted so both share it: `AnimatedBugTitle` passes fixed
blue/yellow, the thinking shimmer uses `TitleTextField.thinkingColors(for:)`
(title colour as the base, accent blended toward white as the highlight — a
coloured glint that never clashes with the system accent). Reduce Motion
collapses both the reveal and the shimmer to short crossfades — same pattern
as everywhere else, see `BuoyMotion.swift`.

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

**Dragging is confined to the grip.** A drag can only begin inside the leading
`allNotesDragHandleWidth` gutter, where `RowDragHandle` draws its dots on hover.
`NotesOutlineView.mouseDown` records whether the press landed there and
`pasteboardWriterForItem` refuses otherwise, so the row keeps the whole of its
width for clicking, scrolling and its buttons. The grip is deliberately **not**
an `.interactiveRegion` — the press has to fall through to the outline view,
which is the only thing that starts drags. A press on the grip that never
becomes a drag opens nothing.

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

**Panel width** is the window content width minus `overlayHorizontalInset * 2`,
set by `AllNotesOverlay`, not a literal. `AllNotesOverlay` exists because
`ContentView.body` is at the type-checker limit and the panel needs a dozen
closures — keep new All Notes wiring in that file.

### Bug Report Mode

Clicking "Report a Bug" in the Settings window's About page brings the note panel forward, creates an ephemeral note, and sets `bugReportNoteID` in `ContentView`. `isBugReport` is a computed property — navigating away passively exits the mode with no cleanup needed. The `TitleTextField` text color is set to `.clear` so the `AnimatedBugTitle` overlay shows through.

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
| `App/SettingsWindowController.swift` | Native Settings window, activation, position, theme, and level |
| `Views/Settings/` | Sidebar and General, Appearance, Shortcuts, About pages |
| `Helpers/ChromeMetrics.swift` | Regular and compact control sizes; height-triggered density reader |
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

### Off-Screen Drag / Harbor Pill Position
**Bug pattern (fixed in 1.1.3).** `DragEnablingNSView.mouseDragged` (in `WindowDragBlocker.swift`) called `window.setFrameOrigin(...)` with no clamping, so the header could drag the panel up under the menu bar / off any edge into an unreachable spot. The Harbor pill frames (`topCenteredFrame`/`bottomCenteredFrame`) in `enterMinimizedMode`/`updateMinimizedWidth` were likewise unclamped. **Fix:** clamp the dragged origin to `(window.screen ?? NSScreen.main).visibleFrame`, and wrap the pill anchored frames in `clampedToVisibleFrame(...)`. Not OS-dependent — purely a missing clamp.

### NSTextView Cursor Bleed into Overlay Panels
**Fixed.** `BuoyTextView` registers an I-beam `NSTrackingArea` that used to bleed through SwiftUI overlays (All Notes, Update Bubble, onboarding). A view-based overlay (`ArrowCursorOverlay`) could not intercept it because AppKit dispatches `cursorUpdate` to the deepest hit-testable view. `BuoyTextView.suppressesIBeamCursor` now skips `super` while an in-panel overlay is up. `ContentView` updates the flag and re-syncs it in the `textViewRef` callback for the initial onboarding case. The Settings window is independent and does not suppress the panel's cursor. Clickable controls in panel overlays use `pointingHandCursor()` from `WindowDragBlocker.swift`.

### Shift + Scroll Note Navigation

**Critical bug pattern (fixed after 1.4.5).** `DragBlockingScrollView.scrollWheel`
(`Editor/EditorView.swift`) has two gestures: the original horizontal two-finger
swipe, and Shift + scroll. The Shift path originally opened with
`if !event.hasPreciseScrollingDeltas, event.modifierFlags.contains(.shift)`, on
the reasoning that a trackpad or Magic Mouse could just swipe horizontally
instead. **That made the gesture unreachable on the hardware the app actually
runs on.** macOS only transposes Shift + scroll onto the X axis for a *plain
wheel* mouse; a precise device already has a horizontal axis, so it keeps
reporting the movement on Y. The swipe path requires `abs(deltaX) >
abs(deltaY)` at `phase == .began`, so a precise device holding Shift matched
neither branch and just scrolled the text. Anyone on a MacBook trackpad or a
Magic Mouse — i.e. nearly everyone — saw nothing happen.

Rules for this handler:
- **Gate on the modifier, not the device.** `isNavigationModifier(_:)` checks
  Shift is down and Cmd/Option/Control are not, and deliberately ignores Caps
  Lock rather than matching `deviceIndependentFlagsMask` exactly.
- **Pick the axis by magnitude, never by `!= 0`.** A vertical trackpad swipe
  always carries a little X jitter, so `scrollingDeltaX != 0 ? X : Y` selects
  the jitter and throws away the real movement.
- **Two separation strategies, by device.** Precise devices report a real
  phase, so `navigateByPreciseScroll` latches `hasNavigatedInCurrentGesture`
  on fire and clears it at `.ended`/`.cancelled` — one swipe, exactly one note,
  however far it runs. A plain wheel has no phase, so `navigateByWheel` falls
  back to a time cooldown plus an idle reset; that only *rate-limits* a long
  continuous spin (~one note per 0.35s), it does not reduce it to one.
- **Drop momentum events** (`event.momentumPhase == []`), or the coast after a
  flick keeps firing.
- **Sign convention:** positive delta means *previous*, matching the horizontal
  swipe where a rightward swipe goes back. Direction follows the system's
  natural-scrolling pref rather than normalising against
  `isDirectionInvertedFromDevice`, same as the swipe.

Shift events are consumed either way (never forwarded to `super`), so the
editor does not also scroll while Shift is held.

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

### Settings Window, Colours, Compact Chrome, and Shortcuts

`SettingsWindowController` owns one standard titled window, activated explicitly because Buoy normally runs as an accessory app. Its level and appearance track the note panel. The footer gear opens General; the keyboard button opens Shortcuts. Opening the window never resizes or restores the note panel.

`ChromeMetrics` holds the regular and compact sizes for header, toolbar, and footer controls. `ChromeDensityReader` switches to compact when the full panel is shortened and uses separate enter/exit thresholds so the chrome cannot flicker at the boundary. The Appearance toggle forces compact controls at any height. Editor text keeps `settings.fontSize`. Suspend the reader during the Harbor pill-to-panel restore, when intermediate frame heights are meaningless.

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
Onboarding and the What's New splash animate the panel taller when shown. Settings and Shortcuts are pages in their own window. Key pieces:
- `PanelLayoutMetrics.onboardingOverrideHeight` / `whatsNewOverrideHeight` — target heights
- `AppDelegate.applyOverrideHeight(_ height: CGFloat?)` — pass `nil` to restore; 0.25s easeInEaseOut
- `ContentView` fires `onOverrideHeight` via `.onChange(of: activeFooterOverlayHeight)` and directly in `onAppear` for whichever overlay is already up at first render
- Panel bottom offset from footer: `.padding(.bottom, 43)` in `ContentView`
