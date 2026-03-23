---
name: project_pending_bugs
description: Known bugs and their status, updated after each session
type: project
---

**App status:** All known bugs resolved as of 2026-03-23. Not yet committed.

## Fixed this session (2026-03-23)

- **Launch crash (`NSMutableRLEArray` out of bounds)** — `NoteStore+Migration.swift`: `parseInlineHTML` had dead code calling `stripped.attributes(at: 0, ...)` on a potentially empty `NSAttributedString`. Notes with `<br>`-only content (e.g. "an older note", "divisons") caused it to crash every launch since their `contentRTF` was still empty and migration re-ran every time. Fixed by removing the dead code; `parseInlineHTML` now just strips HTML tags.
- **⌘C / ⌘V / ⌘X not working** — Non-activating panel means the app isn't always frontmost, so ⌘C/V/X went to the other app's menu bar. Fixed by explicitly handling `copy(nil)` / `paste(nil)` / `cut(nil)` in `performKeyEquivalent`.
- **Dark mode random black text** — `didChangeText()` normalized font but not `foregroundColor` in `typingAttributes`; if cursor passed through text with a stale fixed color, new typing inherited it. Fixed by always setting `typingAttributes[.foregroundColor] = NSColor.textColor` in `didChangeText()`. Also call `updateDefaultTypingAttributes()` in `loadRTF()` to reset after note loads.
- **⌘Z doesn't undo bold/italic/underline/link** — `toggleFontTrait`, `applyUnderline`, `insertLink` mutated `textStorage` directly, bypassing NSTextView's undo pipeline. Fixed by wrapping each in `shouldChangeText(in:replacementString:nil)` / `didChangeText()`.

## Fixed prior session (2026-03-21)

- SF Expanded font on title, ⌘A swallowing, context menu duplication, formatting item validation, Apple Notes transfer, paste color normalization, labelColor → textColor, and more. See git history for details.

## Still open

- **Apple Notes transfer -600 error** — Persists despite multiple fix attempts. Likely sandbox/entitlement issue specific to this machine. Needs deeper investigation.

## Why: NSColor.labelColor vs NSColor.textColor
`labelColor` = 85% opacity black → appears grey on glass/transparent backgrounds.
`textColor` = fully opaque black (light) / white (dark) → correct for text view content.
