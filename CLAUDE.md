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
- Manages the `NSStatusItem` (menu bar icon) with left/right-click handling
- Owns the `NoteStore` and `AppSettings` instances passed into SwiftUI
- Registers the global hotkey via `HotkeyService`
- Applies themes by setting `NSAppearance` on the panel

### State Management

- **`NoteStore`** (`@Observable`) — single source of truth for notes; loaded from GRDB, with 1s/0.6s debounced auto-save for content/title respectively. Call `flushPendingSaves()` on termination.

**Debounced-save note-identity critical bug pattern (fixed in 1.4.1+):** `saveTitle`/`saveContent` schedule a `DispatchWorkItem` that fires 0.6s/1s later. That work item must bind the **target note's `id` at schedule time** and pass it to `persistTitle(_:noteID:)`/`persistContent(_:noteID:)` — it must NOT read `currentNote` inside the persist body. Reason: `currentNote` can be repointed before the timer fires, so a lazily-resolved persist writes the edit onto the *wrong* note (symptom: a title you typed on Note A "transfers" to a newly-created note, and A reverts to its old title). `switchNote` guards this by calling `flushPendingSaves()` before repointing; **every other path that reassigns `currentNote` must flush first too** — `createNote()` does. Same "capture identity at schedule time, not execution time" trap as the Harbor-mode `lastFullSizeFrame` bug.
- **`AppSettings`** (Codable struct) — persisted to `~/.buoy/settings.json`; changes broadcast via `NotificationCenter.settingsDidChange`
- **`Note`** (GRDB record) — stores RTF as `Data` (`contentRTF`), timestamps as `Int64` milliseconds

### Rich Text Editor

**`BuoyTextView`** (NSTextView subclass) is the core editing engine:
- Stores/loads RTF via `NSAttributedString`
- Handles all in-app keyboard shortcuts in `keyDown` (⌘N, ⌘⌫, ⌘⏎, ⌘←/→, ⌘K)
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

GRDB migrations are defined in `NoteStore.swift` (`v1_initial`, `v2_contentRTF`, `v3_isPinned`, `v4_pinnedOrder`).

### Key Services

- **`HotkeyService`** — singleton wrapping `KeyboardShortcuts`. Parses Electron-style shortcut strings (`"Option+Cmd+N"`) into `KeyboardShortcuts.Shortcut`.
- **`AppleNotesService`** — writes plain text to a temp file, then runs AppleScript via `osascript` (background queue) to create a new note in Apple Notes.

### Bug Report Mode

Clicking "Report a Bug" in `SettingsPanel` creates an ephemeral note and sets `bugReportNoteID` in `ContentView`. `isBugReport` is a computed property — navigating away passively exits the mode with no cleanup needed. The `TitleTextField` text color is set to `.clear` so the `AnimatedBugTitle` overlay shows through.

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
| `Editor/BuoyTextView.swift` | Core NSTextView with all formatting logic |
| `Views/ContentView.swift` | Root SwiftUI layout and panel state |
| `Views/OnboardingView.swift` | 4-slide carousel onboarding (Welcome, Formatting, Harbor Mode, Bug Report) |
| `Helpers/WindowDragBlocker.swift` | DragBlockingNSView + ArrowCursorOverlay NSViewRepresentables |
| `Helpers/PanelLayoutMetrics.swift` | All window/panel sizing constants |
| `App/MainMenu.swift` | Whole main menu bar (App/Edit/Format/Window) + `EditMenuDelegate` |
| `Helpers/BuoyMotion.swift` | Reduce Motion gate for every movement animation |
| `Helpers/BuoyAppearance.swift` | `BuoyContrast`, semantic `Color.buoy*` tokens, `BuoyFont` scale |
| `Helpers/NotePlainText.swift` | Memoised RTF→plain-text; use instead of decoding inline |

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
**Fixed.** `BuoyTextView` registers an I-beam `NSTrackingArea` that used to bleed through SwiftUI overlay panels (SettingsPanel, AllNotesPanel, ShortcutsPanel, UpdateBubble) — a view-based overlay (`ArrowCursorOverlay`) tried to intercept it but never worked, because AppKit only dispatches `cursorUpdate` to the deepest hit-testable view, and the overlay was excluded from hit testing to let SwiftUI clicks through. **Fix: suppress at the source.** `BuoyTextView.suppressesIBeamCursor: Bool` — when true, `cursorUpdate(with:)` and `mouseMoved(with:)` skip `super`, so the tracking area never sets the I-beam. `ContentView` drives this flag from a dedicated `.onChange` keyed on `showSettings || showShortcuts || showAllNotes || showOnboarding`, and re-syncs it in the `textViewRef` callback (covers the initial-onboarding-visible case, since `onChange` doesn't fire for a value that's already true at first render). Buttons inside overlay panels get the pointing-hand cursor via a shared `pointingHandCursor()` modifier (`WindowDragBlocker.swift`) that pushes/pops `NSCursor.pointingHand` on hover — apply it to every clickable control in a new overlay panel, it was previously duplicated per-file and easy to forget.

### Carousel Onboarding
`OnboardingView.swift` — 4 slides: Welcome (skeumorphic key caps + ShortcutRecorderView), Formatting (live BuoyTextView demo), Harbor Mode (⌘M animates a mini panel to pill), Bug Report (shimmer title via `AnimatedBugTitle`). A local `NSEvent` monitor captures ⌘M during onboarding — on slide 3 it toggles the demo, on all other slides it consumes the event to prevent accidental Harbor Mode. `AnimatedBugTitle` in `HeaderView.swift` is `internal` (not private) so it can be reused in Slide 4. `hasSeenHarborModeTip` remains in `AppSettings` for backwards-compat but is never set.

### Keyboard Shortcuts Panel
`ShortcutsPanel.swift` — shortcuts list ends with `("⌘M", "Harbor Mode")`. Does not include auto-bullet or auto-todo entries.

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

### Overlay Panel Height Override
Settings, Shortcuts, and Onboarding panels animate the window taller when shown. Key pieces:
- `PanelLayoutMetrics.settingsOverrideHeight` / `shortcutsOverrideHeight` / `onboardingOverrideHeight` — target heights
- `AppDelegate.applyOverrideHeight(_ height: CGFloat?)` — pass `nil` to restore; 0.25s easeInEaseOut
- `ContentView` fires `onOverrideHeight` via `.onChange(of: activeFooterOverlayHeight)` and directly in `onAppear` for onboarding
- Panel bottom offset from footer: `.padding(.bottom, 43)` in `ContentView`
