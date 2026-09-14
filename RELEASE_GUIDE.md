
---

## Releasing Guide

The fastest path is the **`/newupdate VERSION`** skill — Claude bumps the version, archives via `xcodebuild`, zips, releases, updates the website, and pushes. No manual Xcode steps required.

The manual breakdown, for reference:

Claude does the following (no Xcode interaction needed):
- [ ] Bump `MARKETING_VERSION` in `Buoy.xcodeproj/project.pbxproj`
- [ ] Draft the release notes, the `changelog.ts` entry, and the
      `WhatsNewRelease` entry, and **wait for the user to approve all three**
- [ ] Prepend the approved entry to `Buoy/Models/WhatsNewCatalog.swift` (its
      `version` must match `MARKETING_VERSION` exactly). Do this *before*
      archiving: the What's New splash is compiled into the app
- [ ] `xcodebuild ... archive` → app at `/tmp/Buoy.xcarchive/Products/Applications/Buoy.app`
- [ ] Zip the app:
  ```bash
  cd "/path/to/export/folder"
  zip -r Buoy-X.X.zip Buoy.app
  ```
- [ ] Create GitHub release:
  ```bash
  gh release create vX.X "/path/to/Buoy-X.X.zip" --repo gabemempin/buoy --title "Buoy X.X Beta" --notes "What's new in this beta."
  ```
- [ ] Update `install.sh` in `buoy-website/public/install.sh` — bump `VERSION="X.X"` (script quits Buoy before installing, then relaunches it via `open -a` once the new version is unzipped in)
- [ ] Commit and push website:
  ```bash
  cd ~/Dev/buoy-website
  git add public/install.sh
  git commit -m "Bump install.sh to vX.X"
  git push
  ```
- [ ] Bump `version.json` in the Buoy repo:
  ```json
  { "version": "X.X", "url": "https://buoy.gabemempin.me/download" }
  ```
- [ ] Commit and push Buoy repo (do this last):
  ```bash
  cd ~/Dev/Buoy
  git add version.json Buoy/Models/WhatsNewCatalog.swift
  git commit -m "Bump version to X.X"
  git push
  ```
- [ ] Verify: Buoy → Settings → Check for Updates → shows new version

---

## Things to Watch Out For

| Risk | What to do |
|------|------------|
| Cloudflare build fails | Run `npx tsc --noEmit` (and `npm run build`) locally first; check `wrangler.jsonc` / `open-next.config.ts` |
| GitHub release URL 404s | Double-check the zip was uploaded to the right repo/tag |
| What's New entry written after the archive | The splash is compiled in. Re-archive, or the shipped build shows nothing |
| `version.json` pushed before website is live | Users see "update available" but download fails — push app repo last |
| Beta user gets "damaged app" error | They downloaded via browser; fix: `xattr -rd com.apple.quarantine /Applications/Buoy.app` |
| Loops send fails / hits wrong segment | Preview the campaign first, confirm audience before hitting Send |
