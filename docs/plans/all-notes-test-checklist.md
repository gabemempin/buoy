# All Notes rewrite — manual test checklist

> **Automated pass, 2026-09-18.** Items marked `[x]` were driven and verified
> with real synthesized input against the running Debug build. Everything still
> marked `[ ]` needs your hands. The drag items below were genuinely exercised —
> a real press, intermediate motion and release — not a single synthetic
> click-drag, so they carry weight.

Everything below is hand-testable in a Debug build. Ordered by risk: the top
group is where a regression would be worst and where the implementation is
newest. Tick as you go; anything that fails, note which section it was in.

## 1. Click vs drag (the bug you hit)

- [x] Click a note row in **All Notes** → it opens and the panel closes. No lift, no flash.
- [ ] Press and hold a row for 2 seconds without moving, release → same as a click, nothing else happens.
- [ ] Drag a **pinned** row and drop it elsewhere in the pinned band → it reorders and **the panel stays open**.
- [x] Drag a row and release somewhere invalid → the card slides back and the panel stays open.
- [ ] Drag a row, release outside the panel entirely → nothing happens, panel stays open.
- [ ] Drag while a search is active → nothing drags at all (drag is off while searching).

## 2. Row buttons (the hit-testing gamble)

These depend on SwiftUI reporting its button frames to AppKit. If the mechanism
is broken they are *silently* dead, so click every one.

- [x] Hover a note row → pin and x appear. Click the pin → it pins, row jumps to the pinned band.
- [x] Click the pin again on the pinned row → unpins.
- [ ] Click the x → delete confirm appears, Return deletes.
- [ ] Hover a folder row → pencil and x appear, both clickable.
- [x] Move between two adjacent rows quickly → buttons follow the pointer, never stick on the row you left.
- [ ] After a drag and drop, move the mouse away → no row keeps its hover buttons.

## 3. Folder rename

- [ ] New folder button → folder appears, already in rename mode, cursor in the field.
- [ ] Type a name, **move the mouse off the row**, then press Return → the typed name is saved, not "New Folder". (This was broken.)
- [ ] Type a name and press Return without moving → saved.
- [ ] Press Escape on a brand-new folder → the folder is removed entirely.
- [ ] Press Return with the name cleared on a brand-new folder → also removed.
- [ ] Rename an **existing** folder to empty and press Return → reverts to "New Folder", folder survives.
- [ ] Rename, then close the panel mid-edit → no crash, no duplicate folder.
- [ ] Start a search → the new-folder button is dimmed and does nothing.
- [ ] With enough pinned notes to fill the list, create a folder → it scrolls into view.

## 4. Folder drag semantics

- [x] Drag a note from **All Notes** onto a folder → count increments, and the note is **still listed in All Notes**.
- [x] Expand that folder → the note is inside it.
- [x] Drag the child **out** to the All Notes section → it leaves the folder; All Notes is unchanged.
- [ ] Drag a child between two other children of the same folder → reorders.
- [ ] Drag a child onto a *different* folder → moves, both counts update.
- [ ] Drag a **pinned** note onto a folder → it is in the pinned band, the folder, and All Notes at once, pin icon in all three.
- [ ] Try to reorder two **All Notes** rows → rejected, card slides back. (All Notes is chronological by design.)
- [ ] Drop a note onto the divider line above All Notes → behaves as "top of All Notes", not a dead zone.
- [ ] Drag a folder row up and down among the other folders → reorders.
- [ ] Try to drag a folder into the pinned band or All Notes → rejected.

## 5. Folder disclosure and persistence

- [ ] Click a folder row anywhere → toggles open/closed.
- [x] Only **one** chevron is visible on a folder row. (AppKit's own triangle should be suppressed.)
- [ ] Collapse a folder, quit Buoy, relaunch → still collapsed.
- [ ] File a note into a **collapsed** folder → the count increments even though nothing expands.

## 6. Folder delete

- [ ] Click a folder's x → confirm dialog, wording says the notes stay in All Notes.
- [ ] Confirm → folder gone, every note that was in it still present in All Notes.
- [ ] Delete a folder with 1 note → copy reads "Its note", not "Its 1 notes".
- [ ] Escape / click outside → cancels, folder survives.

## 7. Sections and layout

- [ ] With no pins and no folders → just a flat All Notes list, no stray dividers.
- [x] With pins but no folders → Pinned, one divider, All Notes.
- [ ] With folders but no pins → Folders, one divider, All Notes.
- [x] Panel is noticeably wider than before and does not overlap the traffic lights at the smallest window size.
- [ ] Resize the window to minimum → panel still fits, no horizontal clipping.

## 8. Search

- [ ] Type in search → sections and folders disappear, flat match list.
- [ ] Clear search → sections come back, folder expansion state preserved.
- [ ] Search matches note *body* text, not just titles.
- [ ] Search with no matches → "No matching notes".

## 9. Accessibility (regressions from removing the tap gesture)

- [ ] VoiceOver on a note row → announces the title, and VO-Space opens the note.
- [ ] VoiceOver on a folder row → announces name, count, expanded state, and VO-Space toggles it.
- [ ] Every icon button announces a name, not "button".
- [ ] System Settings → Reduce Motion on: reordering, filing and unfiling snap instantly with no slide.
- [ ] Reduce Transparency on: the panel is opaque, not glass.
- [ ] Increase Contrast on: dividers and row fills strengthen.

## 10. Things the rewrite touched indirectly

- [x] ⌘⌫ still deletes the current note with its confirm dialog.
- [ ] ⌘← / ⌘→ still navigate notes and are unaffected by folders.
- [ ] Deleting the note that is currently open falls back to a neighbour.
- [ ] Delete a note that is inside a folder → folder count drops, no gap left behind.
- [ ] Harbor Mode (⌘M) while All Notes is open → no crash, panel dismisses cleanly.
- [ ] The cursor stays an arrow over the panel and never turns into an I-beam.

## Found and fixed during the automated pass

- On opening the panel, a row could show its hover controls while the pointer
  was somewhere else entirely, and stay that way until the mouse was moved.
  AppKit delivers `mouseEntered` when the tracking area is installed before the
  row's geometry settles. Hover is now derived from the pointer's real location
  rather than from the enter/exit event, which also covers the missing exit on
  a drag's source row. **Re-check this one**: open the panel without moving the
  mouse and confirm no row shows pin/x controls.

## Known, deliberate

- In the gap directly below an expanded folder's last child, a drop always
  proposes the child slot rather than the level above. Indentation is drawn in
  SwiftUI, so AppKit cannot use pointer x to tell the levels apart. Aim at the
  top half of the next row instead. Feel, not correctness.
