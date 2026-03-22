# Repository Guidelines

## Project Structure & Module Organization

`FloatNotes/` contains the macOS app source. Core areas are `App/` for app lifecycle and panel management, `Editor/` for the AppKit-backed rich text editor, `Models/` for persistence and settings, `Services/` for integrations such as hotkeys and Apple Notes, `Views/` for SwiftUI screens, and `Helpers/` for shared UI and utility code. Assets live in `FloatNotes/Assets.xcassets/` and icon sources are in `FloatNotes Icon.icon/` and `FloatNotes/FloatNotes Icon.icon/`. Project configuration is in `FloatNotes.xcodeproj/`. Reference docs live at `CLAUDE.md`, `SWIFTUI_REWRITE.md`, and `XCODE_SETUP.md`.

## Build, Test, and Development Commands

Open the project in Xcode for normal development:

```bash
open FloatNotes.xcodeproj
```

Build and run with Xcode using the `FloatNotes` scheme and `Sign to Run Locally`. For CLI builds, use:

```bash
xcodebuild -project FloatNotes.xcodeproj -scheme FloatNotes -configuration Debug build
```

This project uses Swift Package Manager through Xcode for `GRDB.swift`, `Sparkle`, `KeyboardShortcuts`, and `LaunchAtLogin-Modern`, so the first build may resolve packages.

## Coding Style & Naming Conventions

Use Swift conventions already present in the codebase: `UpperCamelCase` for types, `lowerCamelCase` for methods and properties, and one primary type per file named after that type, for example `NoteStore.swift` or `HotkeyService.swift`. Match the existing style in each file, including `// MARK:` sections and `#available(macOS 26, *)` guards where platform-specific behavior is needed. Keep SwiftUI views thin when logic belongs in models, services, or AppKit coordinators.

## Testing Guidelines

There is currently no dedicated test target in the project. Until one is added, verify changes by building in Xcode and walking through the behaviors listed in `XCODE_SETUP.md`, especially editor formatting, panel toggling, persistence, and Apple Notes transfer. When adding tests, prefer an `FloatNotesTests` target and name files after the subject under test, such as `NoteStoreTests.swift`.

## Commit & Pull Request Guidelines

Recent history favors short, imperative commit subjects such as `Fix Apple Notes transfer...` and `Remove internal dev docs...`. Keep commits focused and descriptive. Pull requests should include a summary of user-visible changes, affected areas like `Editor/` or `Services/`, manual verification steps, and screenshots or recordings for UI changes.

## Configuration & Data Notes

The app persists data outside the repo in `~/.floating-notes/notes.db` and `~/.floating-notes/settings.json`. Do not commit secrets, signing material, or machine-specific cache output.
