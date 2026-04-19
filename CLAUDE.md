# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Buoy is a native macOS menu bar sticky-note app — a SwiftUI/AppKit rewrite of a prior Electron version. It lives in the menu bar, shows a floating panel on hotkey, and persists notes as RTF in SQLite.

- **Bundle ID:** `GabeMempin.Buoy`
- **Deployment target:** macOS 15.0 (macOS 26 Liquid Glass conditionals via `#available`)
- **Xcode:** 26.3+, Swift 5.9+, File System Synchronization enabled

## Build & Run

Open `Buoy.xcodeproj` in Xcode and press ⌘R. No CLI build system. Code signing is set to "Sign to Run Locally" — no developer account required.

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

GRDB migrations are defined in `NoteStore.swift` (`v1_initial`, `v2_contentRTF`).

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

## Developer Workflows

### Reset Onboarding
```bash
sed -i '' 's/"onboarded":true/"onboarded":false/' ~/.buoy/settings.json
```
The phrases **"invoke onboarding"** or **"reset onboarding"** mean run this command.

### Harbor Mode Spam → Square Panel Bug
**Critical bug pattern:** `enterMinimizedMode()` saves `lastFullSizeFrame = p.frame`. If a restore animation is in flight when this fires, `p.frame` is an intermediate size, corrupting the saved frame. Fix: guard the write with `isMinimizeAnimating: Bool` in AppDelegate. Set the flag before `animatePanel()`, clear it after `minimizedFrameAnimationDuration + 0.05s` via `DispatchQueue.main.asyncAfter`. Both `enterMinimizedMode` and `exitMinimizedMode` set the flag.

### NSTextView Cursor Bleed into Overlay Panels
`BuoyTextView` registers an I-beam `NSTrackingArea` that bleeds through SwiftUI overlay panels. Fix: `ArrowCursorOverlay` in `WindowDragBlocker.swift` overrides `cursorUpdate(with:)` to call `NSCursor.arrow.set()` **without** calling `super`. Apply as `.overlay(ArrowCursorOverlay().allowsHitTesting(false))`. Used in `SettingsPanel` and `AllNotesPanel`.

### Carousel Onboarding
`OnboardingView.swift` — 4 slides: Welcome (skeumorphic key caps + ShortcutRecorderView), Formatting (live BuoyTextView demo), Harbor Mode (⌘M animates a mini panel to pill), Bug Report (shimmer title via `AnimatedBugTitle`). A local `NSEvent` monitor captures ⌘M during onboarding — on slide 3 it toggles the demo, on all other slides it consumes the event to prevent accidental Harbor Mode. `AnimatedBugTitle` in `HeaderView.swift` is `internal` (not private) so it can be reused in Slide 4. `hasSeenHarborModeTip` remains in `AppSettings` for backwards-compat but is never set.

### Keyboard Shortcuts Panel
`ShortcutsPanel.swift` — shortcuts list ends with `("⌘M", "Harbor Mode")`. Does not include auto-bullet or auto-todo entries.

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
