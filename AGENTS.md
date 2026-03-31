# Agent Instructions

This file provides guidance to AI coding agents (Claude Code, OpenAI Codex CLI, Gemini CLI, and others) when working with code in this repository.

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
- Applies themes by setting `NSAppearance` on the app

### State Management

- **`NoteStore`** (`@Observable`) — single source of truth for notes; loaded from GRDB, with 1s/0.6s debounced auto-save for content/title respectively. Call `flushPendingSaves()` on termination.
- **`AppSettings`** (Codable struct) — persisted to `~/.buoy/settings.json`; changes broadcast via `NotificationCenter.settingsDidChange`
- **`Note`** (GRDB record) — stores RTF as `Data` (`contentRTF`), timestamps as `Int64` milliseconds

### View Hierarchy

```
AppDelegate → NSPanel
  └── ContentView (root SwiftUI, ZStack)
        ├── HeaderView        — traffic lights, title field, note nav buttons
        ├── ToolbarView       — bold/italic/underline/bullet/todo/link buttons
        ├── LinkDialog        — inline modal (conditional)
        ├── EditorView        — NSViewRepresentable wrapping BuoyTextView
        ├── FooterView        — timestamps, settings/shortcuts/copy/transfer buttons
        ├── AllNotesPanel     — overlay (top-right anchor)
        ├── SettingsPanel     — overlay (bottom-left anchor)
        └── OnboardingView    — first-run overlay
```

### Rich Text Editor

**`BuoyTextView`** (NSTextView subclass) is the core editing engine:
- Stores/loads RTF via `NSAttributedString`
- Handles all in-app keyboard shortcuts in `keyDown` (⌘N, ⌘⌫, ⌘⏎, ⌘←/→, ⌘K)
- Auto-converts `- ` + Space → bullet `•`, `[] ` + Space → checkbox attachment
- Bullets and todos continue on Enter; empty list line removes the marker
- Toolbar bullet/todo actions should also work on blank lines; `applyBullet(_:)` and `applyTodo(_:)` use `emptyCurrentLineContentRange(for:)` so the marker is inserted before the line break instead of silently no-oping
- `TodoAttachment` is a custom `NSTextAttachment` subclass for checkboxes

**Nested lists (Tab / Shift+Tab):**
- Tab on any bullet/todo line indents one level (max 2 levels); Shift+Tab outdents
- Level 0: `• ` / `☐` at `headIndent=0`; Level 1: `◦ ` / `☐` at `headIndent=20pt`; Level 2: `◦ ` / `☐` at `headIndent=40pt`
- Tab beyond level 2 falls through to default (inserts a literal tab)
- Indent level stored in `NSParagraphStyle.headIndent` — survives RTF round-trips
- `ListIndent` private enum in `BuoyTextView`: `width=20`, `maxNestingLevel=2`
- Key helpers: `indentLevel(at:)`, `setIndentLevel(_:lineStart:isBullet:)`, `handleTab(isShift:)`, `resetParagraphIndent(at:)`
- **Critical bug pattern:** When removing an empty nested marker at end-of-document, always guard `lineStart < storage.length` before calling `resetParagraphIndent` — otherwise the clamp lands on the previous paragraph's `\n` and strips its indent
- After escaping an empty nested line, reset `typingAttributes = normalizedTypingAttributes()` so subsequent typing doesn't inherit the indent

**`EditorView`** wraps it as `NSViewRepresentable`; **`TextViewCoordinator`** relays delegate callbacks (`onHeightChange`, `onSelectionChange`, `onContentChange`).

### Data Persistence

| Data | Location | Format |
|------|----------|--------|
| Notes | `~/.buoy/notes.db` | GRDB SQLite (RTF binary) |
| Settings | `~/.buoy/settings.json` | JSON (Codable) |

GRDB migrations are defined in `NoteStore.swift` (`v1_initial`, `v2_contentRTF`). Legacy HTML→RTF migration from the Electron version lives in `NoteStore+Migration.swift`.

> **Note:** If you have existing notes from the previous app version, run `mv ~/.floating-notes ~/.buoy` in Terminal to preserve them.

### Key Services

- **`HotkeyService`** — singleton wrapping `KeyboardShortcuts`. Parses Electron-style shortcut strings (`"Option+Cmd+N"`) into `KeyboardShortcuts.Shortcut`.
- **`AppleNotesService`** — writes plain text to a temp file, then runs AppleScript via `osascript` (background queue) to create a new note in Apple Notes.

### macOS Version Conditionals

Glass/vibrancy uses `#available(macOS 26, *)`:
- **macOS 26+:** `.glassEffect()` SwiftUI modifier (Liquid Glass)
- **macOS 15:** `NSVisualEffectView` with `.menu` material via `VisualEffectBackground`

The `View+Glass.swift` helper abstracts this behind `.buoyGlass()`.

## Notes for Specific Agents

- **Claude Code** — also reads `CLAUDE.md` (identical content); use `/help` for Claude Code-specific commands.
- **OpenAI Codex CLI** — reads this `AGENTS.md` file automatically.
- **Gemini CLI** — reads `GEMINI.md`; a symlink or copy of this file should be maintained there if Gemini CLI is used.

## Wrap-Up Workflow

- When the user says "wrap up", add any durable implementation details, bug patterns, workflow decisions, or other future-useful findings from the session to `AGENTS.md`.
- Keep `CLAUDE.md` in lockstep with `AGENTS.md` whenever either file changes so Claude Code sees the same instructions and project memory.
- Treat `AGENTS.md`, `CLAUDE.md`, and the `memory/` directory as the persistent repo-level memory for future agent sessions; avoid logging low-value or purely temporary details.

## Key Files

| File | Purpose |
|------|---------|
| `App/AppDelegate.swift` | Window, menu bar, hotkey, theme management |
| `Models/NoteStore.swift` | @Observable data store + GRDB CRUD |
| `Models/AppSettings.swift` | Settings persistence |
| `Editor/BuoyTextView.swift` | Core NSTextView with all formatting logic |
| `Views/ContentView.swift` | Root SwiftUI layout and panel state |
| `SWIFTUI_REWRITE.md` | Full feature specification (authoritative reference) |
| `XCODE_SETUP.md` | Step-by-step Xcode configuration guide |
