# FloatNotes (Swift) — SwiftUI Native App Guide (macOS 26 Tahoe)

> **Note:** This is the **SwiftUI rewrite** of FloatNotes. The original Electron app lives in a separate repository. This document covers the native macOS SwiftUI version only — not the Electron app.

This document contains everything needed to build FloatNotes (Swift) as a native macOS SwiftUI app targeting macOS 26. It references the prior Electron behavior only as context for what to replicate or improve. Read it fully before writing any code.

---

## App Identity

- **App name:** FloatNotes
- **Bundle ID:** `com.floatnotes.app` (or similar)
- **Type:** macOS menu bar app — no persistent Dock presence by default
- **GitHub:** `kristofbernal/floatnotes`
- **Current Electron version:** 1.1.3

---

## What This App Does

FloatNotes is a frameless, always-on-top floating notepad that lives in the macOS menu bar. The user toggles it with a global hotkey (default ⌥⌘N) or by clicking the tray icon. Notes are stored locally in SQLite. The window is transparent with macOS vibrancy/Liquid Glass. There is no cloud sync, no login, no Dock icon by default.

---

## Window Behavior

| Property | Electron value | SwiftUI equivalent |
|---|---|---|
| Size | 380×300 (compact), 380×680 (expanded) | `NSPanel` or `NSWindow`, fixed width |
| Min size | 340×200 | enforce in window delegate |
| Max height | 700 | enforce in window delegate |
| Always on top | `setAlwaysOnTop(true, 'status')` | `window.level = .statusBar` |
| Frameless | `frame: false` | `NSPanel` with `.borderless` style mask |
| Transparent | `transparent: true` | `window.isOpaque = false`, `window.backgroundColor = .clear` |
| Vibrancy | `vibrancy: 'under-window'` | `NSVisualEffectView` with `.underWindow` material, `.active` state — use only on macOS ≤25; see Liquid Glass note below |
| Liquid Glass | `electron-liquid-glass` (removed — not applicable) | `.glassEffect()` SwiftUI modifier or `NSGlassEffectView` (macOS 26+); do NOT layer `NSVisualEffectView` over glass elements |
| Dynamic resize | animated via `setSize` with ease-out curve | `withAnimation(.easeOut(duration: 0.15))` on window frame or view height |
| Hide on close | window hides, app stays alive | `applicationShouldTerminateAfterLastWindowClosed` → `false`; `window.close()` hides |
| Dock visibility | toggled via `app.dock.show/hide()` | `NSApp.setActivationPolicy(.accessory)` vs `.regular` |
| Dock click shows window | `app.on('activate')` | `applicationShouldHandleReopen` in `AppDelegate` |

### Window height resizing

In Electron, window height animates via a 12-step ease-out curve (150ms) when switching notes. In SwiftUI, use `withAnimation(.easeOut(duration: 0.15))` on a `@State var windowHeight: CGFloat` that drives the window's `setContentSize`.

Content height is measured by fitting the text, then clamped: `max(200, min(700, contentHeight + chromeHeight))`.

- **Grow only while typing** (don't shrink on every keystroke)
- **Allow shrink when switching notes**

---

## Tray / Menu Bar Icon

- Icon file: `resources/icon.png` (1024×1024, colored — not a template image)
- Displayed at 16×16 in the menu bar
- **Do NOT use template image** — this icon is colored and should not be inverted
- Left-click: toggle window show/hide
- Right-click context menu:
  - Settings
  - Check for Updates
  - separator
  - Quit FloatNotes

In SwiftUI: use `NSStatusItem` with `NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)`. Set the icon via `statusItem.button?.image`.

---

## Global Hotkey

- Default: **⌥⌘N** (Option+Cmd+N)
- User-configurable in Settings panel (recorded via a key capture UI)
- Stored in settings as an Electron accelerator string e.g. `"Option+Cmd+N"`
- In SwiftUI: use `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` or the `KeyboardShortcuts` Swift package (recommended)
- Reserved shortcuts that must be blocked: `Cmd+Space`, `Cmd+Tab`, `Cmd+Shift+3`, `Cmd+Shift+4`, `Cmd+Shift+5`
- If the requested shortcut fails to register, roll back to the previous valid one

---

## Data Layer

### SQLite schema

```sql
CREATE TABLE IF NOT EXISTS notes (
  id TEXT PRIMARY KEY,        -- Date.now() as string (e.g. "1710000000000")
  title TEXT NOT NULL,
  content TEXT NOT NULL,      -- stored as HTML in Electron; see note below
  createdAt INTEGER NOT NULL, -- Unix ms timestamp
  updatedAt INTEGER NOT NULL
);
```

**Content format in Electron:** HTML strings like `<div><b>hello</b></div>`. Bullet points are stored as plain text prefix `• ` (Unicode bullet U+2022 + space), not `<ul>`. To-do items are stored as `<span class="todo-check"></span> ` or `<span class="todo-check checked"></span> `.

**Recommended approach for Swift:** Store content as an `NSAttributedString` archive or a custom lightweight format. Do NOT replicate HTML — it was a workaround in Electron. Design a clean storage format in Swift (e.g. RTF data, or a custom JSON/Markdown format). Provide a one-time migration path from old HTML if needed.

### Storage path

- DB: `~/.floating-notes/notes.db`
- Settings: `~/.floating-notes/settings.json`

Keep the same paths for user data continuity. Use `FileManager.default.homeDirectoryForCurrentUser`.

### Note IDs

Currently `Date.now().toString()` (Unix ms as string). Fine to keep or migrate to `UUID`.

### Auto-save

Notes auto-save 1 second after the last keystroke (debounce). Title auto-saves 600ms after the last keystroke. Use `DispatchWorkItem` or `Task.sleep` for debounce.

### Note operations

- **Get all notes:** `SELECT id, title FROM notes ORDER BY createdAt ASC`
- **Get note:** `SELECT * FROM notes WHERE id = ?`
- **Save content:** `UPDATE notes SET content = ?, updatedAt = ? WHERE id = ?`
- **Save title:** `UPDATE notes SET title = ?, updatedAt = ? WHERE id = ?`
- **Create note:** `INSERT INTO notes (id, title, content, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)`; title = `"Note N"` where N = count + 1
- **Delete note:** `DELETE FROM notes WHERE id = ?`; then switch to first remaining note, or create a new `"Note 1"` if none remain
- **Navigate notes:** cycle through notes ordered by `createdAt ASC`; wrap around at both ends

Recommended SQLite package: **GRDB.swift** (type-safe, Swift-native).

---

## Settings

Persisted at `~/.floating-notes/settings.json`. Use `JSONEncoder`/`JSONDecoder` with a `Codable` struct.

```swift
struct AppSettings: Codable {
    var showInDock: Bool = false
    var alwaysOnTop: Bool = true
    var launchAtLogin: Bool = false
    var fontSize: FontSize = .medium    // "small" | "medium" | "large"
    var theme: AppTheme = .system       // "system" | "light" | "dark"
    var globalShortcut: String = "Option+Cmd+N"
    var onboarded: Bool = false
}
```

### Font sizes
| Setting | CSS equivalent | Suggested Swift pt |
|---|---|---|
| small | 11px | 11 |
| medium | 13px | 13 |
| large | 15px | 15 |

### Theme
- `system` → follow `NSApp.effectiveAppearance`
- `light` → force light
- `dark` → force dark

Apply via `window.appearance = NSAppearance(named: ...)`.

### Launch at login
Use `SMAppService.mainApp.register()` / `.unregister()` (macOS 13+) or the `LaunchAtLogin` Swift package.

### Show in Dock
`NSApp.setActivationPolicy(.accessory)` = no dock, `.regular` = show in dock.

### Always on Top
`window.level = .statusBar` vs `.normal`.

---

## Text Editing

This is the hardest part of the rewrite. The Electron app uses a `contenteditable` div with `document.execCommand` for formatting. In SwiftUI/AppKit you have two options:

### Option A: NSTextView (recommended)
Wrap `NSTextView` in `NSViewRepresentable`. Gives you full control over:
- Bold/italic/underline via `NSAttributedString` attributes
- Custom bullet prefix behavior
- To-do checkbox insertion as `NSTextAttachment`
- Right-click menu
- Paste handling

### Option B: SwiftUI TextEditor
Too limited — no attributed text support in current SwiftUI.

### Formatting toolbar buttons
The toolbar has these buttons (all SF Symbols in the native app):

1. **Bold** (⌘B) — `bold`
2. **Italic** (⌘I) — `italic`
3. **Underline** (⌘U) — `underline`
4. separator
5. **Bullet** — `list.bullet`
6. **To-do** — `checklist`
7. separator
8. **Link** — `link`

### Bullet behavior
- Prefix `• ` is a plain text character (U+2022 + space), not a list element
- Typing `- ` then Space auto-converts to `• `
- Pressing Enter on a bullet line continues the bullet on the next line
- Pressing Enter on an **empty** bullet line removes the prefix and exits list mode
- Clicking bullet on a to-do line converts it to bullet (removes checkbox, adds `• `)
- Multi-line selection: clicking bullet converts all selected lines

### To-do behavior
- Checkbox is an inline element — use a custom `NSTextAttachment` subclass in Swift
- Typing `[]` then Space auto-converts to a checkbox
- Clicking the checkbox toggles checked/unchecked state
- Pressing Backspace on an empty to-do line clears the checkbox and exits list mode
- Pressing Enter on a to-do line inserts a new unchecked to-do on the next line
- Pressing Enter on an **empty** to-do line removes it and exits list mode
- Multi-line selection: clicking to-do converts all selected lines

### Paste handling
When pasting onto a bullet or to-do line, strip duplicate prefixes from the pasted text. Always paste as plain text on those lines.

### Right-click context menu
Shows a pill-shaped floating toolbar above the cursor when text is selected:
- **B** (bold), **I** (italic), **U** (underline), separator, **link icon**
- Replicate the pill UI using a floating `NSPanel` or `popover` positioned near the selection rect
- Selection must be preserved when the menu is shown (use `mouseDown` preventDefault equivalent)

### Link insertion
- Toolbar link button opens an inline dialog (not a system sheet) with two fields: Text, URL
- If text is already selected when link is opened, pre-fill the Text field
- URL field: if user omits `https://`, prepend it automatically
- Keyboard: Enter in URL field submits; Enter in Text field moves focus to URL; Escape cancels

---

## UI Layout

```
┌─────────────────────────────────────┐
│ ● ● ●  [Title field]  [≡] [+] [🗑] │  ← traffic lights + header
├─────────────────────────────────────┤
│ [B] [I] [U] | [•] [☐] | [🔗]       │  ← toolbar
├─────────────────────────────────────┤
│  (link dialog — inline, when open)  │
├─────────────────────────────────────┤
│                                     │
│  Editor (NSTextView)                │  ← flex-grows
│                                     │
├─────────────────────────────────────┤
│  Created: …   Last edited: …        │  ← timestamps, right-aligned, 10pt
├─────────────────────────────────────┤
│ [⌨] [⚙]   [Transfer to Apple Notes] [Copy ⌘⏎] │
└─────────────────────────────────────┘
```

Window width: fixed 380pt. Window padding: 8pt all sides, 32pt top (room for traffic lights).

### Traffic lights
Custom colored circles (not native title bar buttons — window is frameless):
- Red `#FF5F57` — hides window (does not quit)
- Yellow `#FEBC2E` — minimizes window (`window.miniaturize`)
- Green `#28C840` — toggles between compact (300pt) and expanded (680pt) height

Position: absolute top-left at `(12, 10)`, gap 6pt between dots, each 12×12pt circle.

### Panels (pop-out overlays)
Three panels that overlay the window content (not separate windows). Only one can be open at a time.

**All Notes panel** — anchors top-right (below header), width 214pt:
- List of all notes: title + delete (✕) button per row
- Active note is highlighted (bold, stronger background)
- Delete button is hidden until hover
- Clicking a note switches to it and closes the panel
- Cannot delete the last note — show error notification instead

**Settings panel** — anchors bottom-left (above footer), width 260pt:
- Toggle rows: Show in Dock, Always on Top, Launch at Login
- Segmented control: Font Size (S / M / L)
- Segmented control: Theme (Auto / Light / Dark)
- Global shortcut recorder (see below)
- Footer: "Check for Updates" button + "Quit FloatNotes" danger button

**Keyboard Shortcuts panel** — anchors bottom-left (above footer), width 248pt:
- Static list of all shortcuts (see keyboard shortcuts table below)
- Toggle shortcut row shows the user's currently configured shortcut

All panels share:
- Glass background: `.glassEffect()` modifier (macOS 26+); fall back to `NSVisualEffectView` with `.menu` or `.popover` material on macOS ≤25
- 14pt corner radius
- Appear animation: scale from 0.92 + fade in, 160ms ease-out, origin at anchor corner
- ✕ close button in header

### Timestamps
Below the editor, above the footer. Right-aligned, 10pt, secondary text color.
- Format: `Created: [time]  Last edited: [time]`
- Same day → time only: `2:34 PM`
- Yesterday → `Yesterday 2:34 PM`
- Older → `Mar 18 2:34 PM`

### Notification toast
- Small rounded rectangle, fixed bottom-right corner of window
- Accent color background, white text, 11pt
- Fades in, stays 2 seconds, fades out
- Red background (`#FF3B30`) for error messages
- Messages used: `"Copied to clipboard"`, `"Transferred to Apple Notes"`, `"Cannot delete the last note"`, `"Error: …"`

---

## Keyboard Shortcuts (in-app)

| Shortcut | Action |
|---|---|
| ⌘B | Bold |
| ⌘I | Italic |
| ⌘U | Underline |
| ⌘N | New note |
| ⌘⌫ | Delete current note |
| ⌘⏎ | Copy to clipboard |
| ⌘← | Previous note (wraps) |
| ⌘→ | Next note (wraps) |
| `-` + Space | Auto-convert to bullet `•` |
| `[]` + Space | Auto-convert to to-do checkbox |
| Tab (in title field) | Move focus to editor |

---

## Global Shortcut Recorder UI

A custom key-capture control used in both the onboarding screen and Settings panel:
- Displays current shortcut as symbol string (e.g. `⌥⌘N`)
- "Edit" / "Customize" button puts it into recording mode
- Recording mode: border pulses blue, shows hint text "Press your desired key combination…"
- User presses a key combo → if valid, saves immediately and exits recording
- If reserved combo: shows "Reserved!" briefly, then reverts
- Escape cancels recording without saving

Validation: must include ⌘, ⌃, or ⌥. Must not be a system-reserved combo.

Accelerator → display symbol mapping:
```
Cmd    → ⌘
Ctrl   → ⌃
Option → ⌥
Shift  → ⇧
Return → ⏎
Backspace → ⌫
Delete → ⌦
Escape → ⎋
Space  → ␣
```

---

## Copy & Transfer

### Copy to Clipboard
- "Copy" button in footer with `⌘⏎` hint
- Copies **plain text** — strips all formatting, HTML, prefixes
- `NSPasteboard.general.setString(plainText, forType: .string)`

### Transfer to Apple Notes
- "Transfer to Apple Notes" button in footer
- Sends plain text to Apple Notes via AppleScript:
```applescript
tell application "Notes"
  make new note at default account with properties {body: noteBody}
end tell
```
- In Swift: write content to a temp file, run `osascript` via `Process`, or use `NSAppleScript`
- On success: show "Transferred to Apple Notes" toast
- On failure: show "Error: …" toast

---

## Auto-Updater

The Electron app uses a custom DIY updater because it's unsigned. In SwiftUI, use **Sparkle**.

Sparkle setup:
1. Add Sparkle via Swift Package Manager
2. Host an appcast XML at a stable URL (GitHub Pages or raw GitHub)
3. Add `SUFeedURL` to `Info.plist`
4. Trigger manual check from the app menu ("Check for Updates…") and from the Settings panel button

Update UI in Settings panel:
- Default state: "Check for Updates" button
- After check with no update: shows "You're up to date (v1.x.x)!" for 3 seconds, then reverts
- After update downloaded (Sparkle handles this): Sparkle's own UI takes over for install/relaunch

---

## Onboarding (First Run)

Shown when `settings.onboarded == false`.

Full-window overlay on top of main content:
- App icon (80×80, rounded 18pt corners)
- Title: "Welcome to FloatNotes" (18pt bold, centered)
- Subtitle: "A floating notepad that lives in your menu bar." (12pt, secondary, centered)
- Feature pills (3 rows):
  - "Always on top of other windows"
  - "Notes saved automatically"
  - "Toggle with a global shortcut"
- Global shortcut recorder section with "Customize" button
- "Get Started" CTA button (accent color, full width)

On dismiss: set `onboarded = true` and save settings.

To re-trigger: delete `~/.floating-notes/settings.json` or set `"onboarded": false` in it.

---

## Application Menu

```
FloatNotes
  About FloatNotes
  ─────────────────
  Check for Updates…
  ─────────────────
  Hide FloatNotes        ⌘H
  Hide Others            ⌥⌘H
  Show All
  ─────────────────
  Quit FloatNotes        ⌘Q

Edit
  Undo    ⌘Z
  Redo    ⇧⌘Z
  ─────────────────
  Cut     ⌘X
  Copy    ⌘C
  Paste   ⌘V
  Select All  ⌘A

Window
  Minimize    ⌘M
  Zoom
  ─────────────────
  Bring All to Front
```

---

## Colors & Appearance

### Color tokens
| Token | Light | Dark |
|---|---|---|
| Text primary | `#000` | `#fff` |
| Text secondary | `#555` | `#bbb` |
| Accent | `#007AFF` | `#0A84FF` |
| Border | `rgba(0,0,0,0.12)` | `rgba(255,255,255,0.12)` |
| Button hover | `rgba(0,0,0,0.07)` | `rgba(255,255,255,0.10)` |
| Button hover strong | `rgba(0,0,0,0.13)` | `rgba(255,255,255,0.17)` |
| Panel background | `rgba(242,242,242,0.98)` | `rgba(38,38,38,0.98)` |
| Danger | `#FF3B30` | `#FF3B30` |

Use `Color(.labelColor)`, `Color(.secondaryLabelColor)`, `Color(.controlAccentColor)` where possible to follow system appearance automatically.

### Selection highlight
In Electron, `systemPreferences.getAccentColor()` is read and applied at reduced opacity for text selection color. In Swift, `NSColor.controlAccentColor` is available natively — use it with reduced opacity for `NSTextView` selection color.

### App icon
- Source: `resources/icon.icon` (Icon Composer bundle)
- Compiled: `resources/compiled-icon/FloatNotes Icon.icns` and `Assets.car`
- Variants: Light, Dark, Clear, Tinted (for macOS 26 Tahoe adaptive icons)
- Copy `Assets.car` and `.icns` into the Xcode project's asset catalog

---

## Architecture Recommendation

```
Flote/
├── App/
│   ├── FloteApp.swift              # @main, AppDelegate
│   └── AppDelegate.swift           # window setup, NSStatusItem, global hotkey
├── Models/
│   ├── Note.swift                  # Codable struct
│   ├── AppSettings.swift           # Codable struct + load/save
│   └── NoteStore.swift             # GRDB-backed, @Observable
├── Views/
│   ├── ContentView.swift           # root layout
│   ├── EditorView.swift            # NSTextView wrapped in NSViewRepresentable
│   ├── ToolbarView.swift
│   ├── HeaderView.swift
│   ├── FooterView.swift
│   ├── Panels/
│   │   ├── AllNotesPanel.swift
│   │   ├── SettingsPanel.swift
│   │   └── ShortcutsPanel.swift
│   ├── LinkDialog.swift
│   ├── OnboardingView.swift
│   └── ContextMenuPill.swift       # right-click floating pill menu
├── Services/
│   ├── HotkeyService.swift         # global shortcut registration
│   └── AppleNotesService.swift     # AppleScript bridge
└── Resources/
    ├── Assets.xcassets
    └── FloatNotes Icon.icns
```

Use `@Observable` (Swift 5.9+ / macOS 14+) or `ObservableObject` for `NoteStore` and settings. `NoteStore` is the single source of truth passed via `.environment`.

**Deployment target: macOS 26** (Tahoe). This enables:
- Native `.glassEffect()` modifier for Liquid Glass on panels and window chrome
- `NSGlassEffectView` for AppKit surfaces
- `GlassEffectContainer` for grouping multiple glass elements (glass cannot sample other glass — wrap siblings in a container)
- `glassEffectID` modifier for fluid morphing animations between glass views
- Adaptive app icon variants (Light / Dark / Clear / Tinted) are a macOS 26 requirement

---

## Known Electron Quirks NOT to Replicate

- **Vibrancy freeze bug** — Electron needed `setVibrancy(null)` → `setVibrancy('under-window')` on blur to prevent frozen backdrop. Native `NSVisualEffectView` / `NSGlassEffectView` do not have this bug.
- **`electron-liquid-glass` package** — The Electron third-party Liquid Glass shim is gone entirely. Use SwiftUI's native `.glassEffect()` modifier or `NSGlassEffectView` for AppKit. Note: `NSVisualEffectView` in the view hierarchy blocks Liquid Glass from rendering on macOS 26 — remove it and replace with `.glassEffect()` instead.
- **`setAlwaysOnTop(true, 'status')`** — Native `window.level = .statusBar` is the direct equivalent and works correctly without workarounds.
- **`backgroundThrottling: false`** — Not needed in native apps.
- **`contextIsolation`, `sandbox`, `preload.js`** — Electron security model. Not applicable.
- **IPC (renderer ↔ main process)** — The entire split is gone. All logic is in one Swift process.
- **`document.execCommand`** — Deprecated web API. Use `NSTextView` attributed string APIs.
- **HTML as storage format** — Electron stored note content as raw HTML. Do not replicate this; design a clean native format.

---

## Feature Checklist

- [ ] SQLite persistence (GRDB.swift)
- [ ] Settings persistence (JSON, same path `~/.floating-notes/settings.json`)
- [ ] Menu bar tray icon (colored, not template)
- [ ] Toggle window via tray left-click
- [ ] Tray right-click context menu
- [ ] Global hotkey (default ⌥⌘N, user-configurable)
- [ ] Frameless transparent window with vibrancy
- [ ] Always-on-top behavior (`window.level = .statusBar`)
- [ ] Custom traffic light buttons (hide / minimize / expand-toggle)
- [ ] Note title field with tab-to-editor
- [ ] NSTextView editor with auto-save (1s debounce)
- [ ] Bold / Italic / Underline toolbar + keyboard shortcuts
- [ ] Bullet point behavior (prefix, Enter continuation, auto-format from `- `)
- [ ] To-do checkbox behavior (NSTextAttachment, toggle, Enter, auto-format from `[]`)
- [ ] Link insertion inline dialog
- [ ] Right-click pill context menu (B/I/U/link)
- [ ] All Notes panel
- [ ] Settings panel with all toggles and controls
- [ ] Keyboard Shortcuts panel
- [ ] Animated window height resize on note switch and typing
- [ ] Note navigation ⌘← / ⌘→ (wraps)
- [ ] Copy to clipboard (⌘⏎, plain text)
- [ ] Transfer to Apple Notes (AppleScript)
- [ ] Timestamps display (created + last edited)
- [ ] Notification toast (success + error)
- [ ] Onboarding overlay (first run, `onboarded` flag)
- [ ] Global shortcut recorder UI (in onboarding + settings)
- [ ] Show/hide Dock icon setting
- [ ] Launch at login setting
- [ ] Theme override (Auto/Light/Dark)
- [ ] Font size setting (S/M/L)
- [ ] Accent color for selection highlight
- [ ] Sparkle auto-updater
- [ ] Native app menu (FloatNotes / Edit / Window)
- [ ] Dock click shows hidden window
- [ ] App icon with all variants (Light/Dark/Clear/Tinted)
