# Buoy Beta Release Checklist

A linear, top-to-bottom guide for shipping the first beta. Work through each phase in order — the ordering matters (website must be live before you push `version.json`).

## What Claude Already Did
- [x] Fixed `UpdateService.swift` — feed URL now points to `gabemempin/buoy`
- [x] Fixed `version.json` — `url` field updated to `/download`
- [x] Fixed `RELEASING.md` — all repo references updated to `gabemempin/buoy`

## What You Still Need to Do
- [x] Fix nested todo indent bug (Phase 1)
- [x] Archive in Xcode + zip the `.app` (Phase 3)
- [x] Create GitHub release with `gh` CLI (Phase 4)
- [x] Build `/download` page + `install.sh` on website (Phase 5)
- [x] Test locally and deploy to Netlify (Phases 6–7)
- [ ] Push Buoy app repo (Phase 8)
- [ ] Design + send beta email, post on Instagram (Phases 9–11)

---

## Phase 1 — Fix the Nested Todo Bug ✅ (done by Claude)
- [x] Investigate why `headIndent` isn't persisting for nested todos across relaunch
- [x] Fix `BuoyTextView.swift` — save side preserves `headIndent` in RTF marker; load side reads it back before restoring attachment
- [x] Verified by user: nested indent persists across relaunch

---

## Phase 2 — Pre-Push Code Fixes ✅ (done by Claude)
- [x] **`UpdateService.swift`** — Updated feed URL to `gabemempin/buoy` (was `kristofbernal/buoy`)
- [x] **`version.json`** — Updated `url` field to `/download` (was `/install`)
- [x] **`RELEASING.md`** — Fixed all repo references to `gabemempin/buoy`
- [x] Commit all changes

---

## Phase 3 — Build & Export ✅
- [x] Confirm version is `1.0`: Xcode → Buoy target → General → Version
- [x] Product → Archive → Distribute App → Copy App → save `.app` (Xcode creates a dated subfolder, e.g. `Buoy 2026-04-04 12-22-04/`)
- [x] Zip:
  ```bash
  cd "/Users/gabemempin/Dev/Buoy/Buoy 2026-04-04 12-22-04"
  zip -r Buoy-1.0.zip Buoy.app
  ```

---

## Phase 4 — GitHub Release ✅
- [x] Create the release (requires `gh` CLI — run `brew install gh` if missing):
  ```bash
  gh release create v1.0 "/Users/gabemempin/Dev/Buoy/Buoy 2026-04-04 12-22-04/Buoy-1.0.zip" \
    --repo gabemempin/buoy \
    --title "Buoy 1.0 Beta" \
    --notes "First beta release. Requires macOS 15.0 or later."
  ```
- [x] Note the permanent download URL:
  ```
  https://github.com/gabemempin/buoy/releases/download/v1.0/Buoy-1.0.zip
  ```

---

## Phase 5 — Website Assets & Download Page ✅

### 5.1 — Take Screenshots
Take these in the app (⌘⇧4 → Space → click window):
- [x] Light mode — empty note (clean slate)
- [x] Dark mode — note with some bullet/todo content
- [x] AllNotes panel open
- [x] SettingsPanel open

Save them to `buoy-website/public/screenshots/` as:
`hero-light.png`, `hero-dark.png`, `all-notes.png`, `settings.png`

### 5.2 — Feature List (use in download page)
Copy-paste this into the page:
- Menu bar access — always one click away
- Rich text: bold, italic, bullets, nested to-dos
- Multiple notes with instant switching
- Auto-save with RTF persistence
- Global hotkey to show/hide
- Liquid Glass design (macOS 26) / vibrancy (macOS 15)
- Free beta — no account required

### 5.3 — Create `install.sh` ✅
Create `buoy-website/public/install.sh`:
```sh
#!/bin/sh
set -e

VERSION="1.0"
ZIP_URL="https://github.com/gabemempin/buoy/releases/download/v${VERSION}/Buoy-${VERSION}.zip"

echo "Installing Buoy ${VERSION}..."
curl -fsSL "$ZIP_URL" -o /tmp/Buoy.zip
unzip -qo /tmp/Buoy.zip -d /Applications/
rm /tmp/Buoy.zip
echo "Done. Launch Buoy from /Applications or Spotlight."
```

> **Gatekeeper note:** Installing via `curl` in Terminal skips macOS's quarantine check, so users won't see the "unidentified developer" popup. If a user downloads the `.zip` manually through Safari and gets a "damaged" error, they should run:
> ```bash
> xattr -rd com.apple.quarantine /Applications/Buoy.app
> ```

### 5.4 — Create the `/download` Page ✅
Create `buoy-website/app/download/page.tsx` with:
- [x] Hero screenshot (light/dark toggle)
- [x] Feature list (from 5.2)
- [x] Install command in a copyable code block:
  ```
  curl -fsSL https://buoy.gabemempin.me/install.sh | sh
  ```
- [x] System requirement: macOS 15.0+
- [x] Beta disclaimer: "This is an early beta. Expect rough edges."
- [x] Gatekeeper troubleshooting note (collapsed/small text)

---

## Phase 6 — Test Locally ✅

- [x] `cd ~/Dev/buoy-website && npm run dev`
- [x] Visit `http://localhost:3000/download` — verify layout, copy button, screenshots load
- [x] Test install script against the GitHub release URL directly:
  ```bash
  curl -fsSL https://github.com/gabemempin/buoy/releases/download/v1.0/Buoy-1.0.zip \
    -o /tmp/Buoy-test.zip && unzip -qo /tmp/Buoy-test.zip -d /tmp/BuoyTest/
  ```
  Confirm `Buoy.app` appears and launches.

---

## Phase 7 — Deploy to Netlify

- [ ] Commit all website changes:
  ```bash
  cd ~/Dev/buoy-website
  git add .
  git commit -m "Add download page and install script for v1.0 beta"
  git push
  ```
- [ ] Wait for Netlify deploy (check dashboard or watch the build log)
- [ ] Test the live end-to-end install:
  ```bash
  curl -fsSL https://buoy.gabemempin.me/install.sh | sh
  ```
  Confirm Buoy appears in `/Applications` and launches correctly.
- [ ] Visit `https://buoy.gabemempin.me/download` and verify everything looks right

---

## Phase 8 — Push the Buoy App Repo

> ⚠️ **Do this after Phase 7 is confirmed live.** Pushing `version.json` immediately tells the auto-updater a new version exists — the download link must be working first.

- [ ] Push all commits (bug fix, UpdateService fix, version.json, RELEASING.md):
  ```bash
  cd ~/Dev/Buoy
  git push
  ```
- [ ] Verify auto-update: launch Buoy → Settings → Check for Updates → should show "Up to date"

---

## Phase 9 — Design Beta Email (Canva)

- [x] Open Canva, create a new email design (recommended size: 600×800px)
- [x] Include:
  - Subject line suggestion: **"Buoy beta is here — try it now"**
  - App icon or hero screenshot at the top
  - 2–3 sentence description of what Buoy is
  - Feature highlights (3–5 bullets)
  - Install command in a styled code block or button linking to `/download`
  - Beta disclaimer: "This is an early beta — feedback welcome, things may break"
  - Your contact / reply-to info
- [x] Export as PNG or PDF for use in Loops

---

## Phase 10 — Send Beta Email (Loops)

- [ ] Log into [Loops dashboard](https://app.loops.so)
- [ ] Create a new Campaign
- [ ] Target audience: `waitlist` group
- [ ] Subject: `Buoy beta is here — try it now`
- [ ] Embed/paste the Canva design or build the email in Loops directly
- [ ] Send a test to yourself first — verify links work, install command displays correctly
- [ ] Send to full list

---

## Phase 11 — Instagram Announcement

- [ ] Pick your best screenshot (or use `buoy-website/public/promo.png`)
- [ ] Draft caption — suggested structure:
  ```
  Buoy beta is live. 🌊

  A lightweight menu bar notepad for macOS — always one click away.

  [short feature highlight or 2]

  Download link in bio (macOS 15+ required).
  This is a beta — feedback welcome.
  ```
- [ ] Update link in bio to `buoy.gabemempin.me/download`
- [ ] Post

---

## Releasing Beta 2, 3, Onwards

For each new beta version (e.g. `1.1`, `1.2`):

- [ ] Bump version in Xcode: Buoy target → General → **Version**
- [ ] Product → Archive → Distribute App → Copy App → save `.app`
- [ ] Zip the app:
  ```bash
  cd "/path/to/export/folder"
  zip -r Buoy-X.X.zip Buoy.app
  ```
- [ ] Create GitHub release:
  ```bash
  gh release create vX.X "/path/to/Buoy-X.X.zip" --repo gabemempin/buoy --title "Buoy X.X Beta" --notes "What's new in this beta."
  ```
- [ ] Update `install.sh` in `buoy-website/public/install.sh` — bump `VERSION="X.X"`
- [ ] Commit and push website:
  ```bash
  cd ~/Dev/buoy-website
  git add public/install.sh
  git commit -m "Bump install.sh to vX.X"
  git push
  ```
- [ ] Wait for Netlify to deploy, then test: `curl -fsSL https://buoy.gabemempin.me/install.sh | sh`
- [ ] Bump `version.json` in the Buoy repo:
  ```json
  { "version": "X.X", "url": "https://buoy.gabemempin.me/download" }
  ```
- [ ] Commit and push Buoy repo (do this last):
  ```bash
  cd ~/Dev/Buoy
  git add version.json
  git commit -m "Bump version to X.X"
  git push
  ```
- [ ] Verify: Buoy → Settings → Check for Updates → shows new version

---

## Things to Watch Out For

| Risk | What to do |
|------|------------|
| Netlify build fails | Check `netlify.toml` and that `npm run build` succeeds locally first |
| GitHub release URL 404s | Double-check the zip was uploaded to the right repo/tag |
| `version.json` pushed before website is live | Users see "update available" but download fails — push app repo last |
| Beta user gets "damaged app" error | They downloaded via browser; fix: `xattr -rd com.apple.quarantine /Applications/Buoy.app` |
| Loops send fails / hits wrong segment | Preview the campaign first, confirm audience before hitting Send |
