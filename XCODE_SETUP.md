# Xcode Project Setup for FloatNotes (Swift)

## 1. Create New Project

- Xcode → File → New → Project → **macOS → App**
- Product Name: `FloatNotes`
- Bundle ID: `com.floatnotes.app`
- Interface: **SwiftUI**
- Language: **Swift**
- Deployment Target: **macOS 15.0**

## 2. Delete auto-generated stub

Delete the auto-generated `ContentView.swift` that Xcode creates.

## 3. Add Swift Package Dependencies

File → Add Package Dependencies → add all four:

| Package | URL |
|---|---|
| GRDB.swift | `https://github.com/groue/GRDB.swift` |
| Sparkle | `https://github.com/sparkle-project/Sparkle` |
| KeyboardShortcuts | `https://github.com/sindresorhus/KeyboardShortcuts` |
| LaunchAtLogin-Modern | `https://github.com/sindresorhus/LaunchAtLogin-Modern` |

For Sparkle, add both the `Sparkle` library AND the `Sparkle XPC Service` target to your app target.

## 4. Drag in the generated Swift files

From `FloatNotes (Swift)/FloatNotes/`, drag all folders into the Xcode project navigator, preserving the group structure:

```
App/
Editor/
Helpers/
Models/
Services/
Views/
Views/Panels/
```

Make sure all files are added to the `FloatNotes` target.

## 5. Info.plist entries

Add these keys to your `Info.plist`:

| Key | Type | Value |
|---|---|---|
| `LSUIElement` | Boolean | YES |
| `SUFeedURL` | String | *(your appcast URL)* |
| `SUPublicEDKey` | String | *(from Sparkle key generation)* |
| `SUEnableAutomaticChecks` | Boolean | NO |

## 6. Assets.xcassets

- Add your app icon as `AppIcon` (all required sizes)
- Add a menu bar icon named `MenuBarIcon` (colored, **not** a template image) — ideally 44×44pt @2x

## 7. Code Signing

- Build Settings → Signing → **Sign to Run Locally** (no developer account needed)
- Remove any entitlements file — not needed since app is unsigned/unsandboxed

## 8. Sparkle EdDSA Keys (optional for auto-updates)

```bash
# In Sparkle package directory:
./bin/generate_keys
# Copy the public key into Info.plist SUPublicEDKey
# Keep the private key safe — used to sign update packages
```

## 9. First Launch

Since the app is unsigned, users must right-click → Open on first launch to bypass Gatekeeper. After that, normal double-click works.

## Verification Checklist

- [ ] App launches as menu bar only (no Dock icon)
- [ ] Left-click tray icon toggles the panel
- [ ] Right-click shows Settings / Check for Updates / Quit menu
- [ ] ⌥⌘N global hotkey toggles panel from any app
- [ ] Existing notes load from `~/.floating-notes/notes.db`
- [ ] Bold/Italic/Underline formatting works and persists
- [ ] Bullet auto-format: type `- ` then Space → `• `
- [ ] Todo auto-format: type `[] ` then Space → checkbox
- [ ] Clicking checkbox toggles checked/unchecked
- [ ] All Notes panel lists and switches notes
- [ ] Settings toggles (Show in Dock, Always on Top, etc.) persist
- [ ] Transfer to Apple Notes creates a note
- [ ] Copy (⌘⏎) copies plain text
- [ ] Onboarding shown on first launch
- [ ] macOS 15: vibrancy background renders correctly
- [ ] macOS 26: Liquid Glass renders correctly
