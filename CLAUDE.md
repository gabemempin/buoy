# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FloatNotes is a native macOS menu bar sticky-note app — a SwiftUI/AppKit rewrite of a prior Electron version. It lives in the menu bar, shows a floating panel on hotkey, and persists notes as RTF in SQLite.

- **Bundle ID:** `com.floatnotes.app`
- **Deployment target:** macOS 15.0 (macOS 26 Liquid Glass conditionals via `#available`)
- **Xcode:** 26.3+, Swift 5.9+, File System Synchronization enabled

## Build & Run

Open `FloatNotes.xcodeproj` in Xcode and press ⌘R. No CLI build system. Code signing is set to "Sign to Run Locally" — no developer account required.

**Swift Package dependencies** (managed via Xcode SPM):
- `GRDB.swift` (groue/GRDB) — SQLite ORM
- `Sparkle` (sparkle-project/Sparkle) — auto-updater
- `KeyboardShortcuts` (sindresorhus/KeyboardShortcuts) — global hotkey registration
- `LaunchAtLogin-Modern` (sindresorhus/LaunchAtLogin-Modern) — login item management

## Architecture

### App Entry & Window Management

`FloatNotes2App.swift` is the `@main` entry. Almost all app logic lives in **`AppDelegate.swift`** (NSApplicationDelegateAdaptor), which:
- Creates a borderless, always-on-top `NSPanel` (non-activating, transparent)
- Manages the `NSStatusItem` (menu bar icon) with left/right-click handling
- Owns the `NoteStore` and `AppSettings` instances passed into SwiftUI
- Registers the global hotkey via `HotkeyService`
- Applies themes by setting `NSAppearance` on the app

### State Management

- **`NoteStore`** (`@Observable`) — single source of truth for notes; loaded from GRDB, with 1s/0.6s debounced auto-save for content/title respectively. Call `flushPendingSaves()` on termination.
- **`AppSettings`** (Codable struct) — persisted to `~/.floating-notes/settings.json`; changes broadcast via `NotificationCenter.settingsDidChange`
- **`Note`** (GRDB record) — stores RTF as `Data` (`contentRTF`), timestamps as `Int64` milliseconds

### View Hierarchy

```
AppDelegate → NSPanel
  └── ContentView (root SwiftUI, ZStack)
        ├── HeaderView        — traffic lights, title field, note nav buttons
        ├── ToolbarView       — bold/italic/underline/bullet/todo/link buttons
        ├── LinkDialog        — inline modal (conditional)
        ├── EditorView        — NSViewRepresentable wrapping FloatNotesTextView
        ├── FooterView        — timestamps, settings/shortcuts/copy/transfer buttons
        ├── AllNotesPanel     — overlay (top-right anchor)
        ├── SettingsPanel     — overlay (bottom-left anchor)
        └── OnboardingView    — first-run overlay
```

### Rich Text Editor

**`FloatNotesTextView`** (NSTextView subclass, 557 lines) is the core editing engine:
- Stores/loads RTF via `NSAttributedString`
- Handles all in-app keyboard shortcuts in `keyDown` (⌘N, ⌘⌫, ⌘⏎, ⌘←/→, ⌘K)
- Auto-converts `- ` + Space → bullet `•`, `[] ` + Space → checkbox attachment
- Bullets continue on Enter; empty bullet line removes bullet
- `TodoAttachment` is a custom `NSTextAttachment` subclass for checkboxes

**`EditorView`** wraps it as `NSViewRepresentable`; **`TextViewCoordinator`** relays delegate callbacks (`onHeightChange`, `onSelectionChange`, `onContentChange`).

### Data Persistence

| Data | Location | Format |
|------|----------|--------|
| Notes | `~/.floating-notes/notes.db` | GRDB SQLite (RTF binary) |
| Settings | `~/.floating-notes/settings.json` | JSON (Codable) |

GRDB migrations are defined in `NoteStore.swift` (`v1_initial`, `v2_contentRTF`). Legacy HTML→RTF migration from the Electron version lives in `NoteStore+Migration.swift`.

### Key Services

- **`HotkeyService`** — singleton wrapping `KeyboardShortcuts`. Parses Electron-style shortcut strings (`"Option+Cmd+N"`) into `KeyboardShortcuts.Shortcut`.
- **`AppleNotesService`** — writes plain text to a temp file, then runs AppleScript via `osascript` (background queue) to create a new note in Apple Notes.

### macOS Version Conditionals

Glass/vibrancy uses `#available(macOS 26, *)`:
- **macOS 26+:** `.glassEffect()` SwiftUI modifier (Liquid Glass)
- **macOS 15:** `NSVisualEffectView` with `.menu` material via `VisualEffectBackground`

The `View+Glass.swift` helper abstracts this behind `.floatNotesGlass()`.

## Key Files

| File | Purpose |
|------|---------|
| `App/AppDelegate.swift` | Window, menu bar, hotkey, theme management |
| `Models/NoteStore.swift` | @Observable data store + GRDB CRUD |
| `Models/AppSettings.swift` | Settings persistence |
| `Editor/FloatNotesTextView.swift` | Core NSTextView with all formatting logic |
| `Views/ContentView.swift` | Root SwiftUI layout and panel state |
| `SWIFTUI_REWRITE.md` | Full feature specification (authoritative reference) |
| `XCODE_SETUP.md` | Step-by-step Xcode configuration guide |
