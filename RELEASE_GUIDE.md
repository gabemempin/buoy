
---

## Releasing Guide

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
