# All Notes: single drag model + folders

Implementation plan, settled with Gabe on 2026-09-18. Written to be executed by
another agent without this conversation. Read `CLAUDE.md` first; every rule in
its "Accessibility & Menu Conventions" section applies to new UI here.

Two phases. Ship and hand-test Phase 1 before starting Phase 2.

- **Phase 1** rebuilds the All Notes list on `NSOutlineView` with exactly one
  drag source and animated commits. No schema change, no new features. The user
  judges the drag feel in isolation.
- **Phase 2** adds one-level folders on top.

---

## Current state (what you are replacing)

Files:

| File | Role today |
|------|-----------|
| `Buoy/Views/Panels/AllNotesPanel.swift` | SwiftUI shell: header + close, search field, `NotesTableViewWrapper`, `NoteRow`. Panel is `.frame(width: 214)`, list `.frame(maxHeight: 300)`. |
| `Buoy/Views/AppKitWrappers.swift` | `SearchFieldWrapper`, `ThemePickerWrapper`, `NoSeparatorRowView`, `NoteRowDragHandle`, `NotesTableViewWrapper` (NSTableView + coordinator). |
| `Buoy/Views/ContentView.swift` lines ~332-365 | Mounts `AllNotesPanel` in a `GeometryReader`, top-trailing, with `allNotesTopInset`/`allNotesBottomInset`/`overlayHorizontalInset` padding. Wires `onSelect` → `noteStore.switchNote`, `onDelete` → `requestDeleteNote`, `onTogglePin`, `onReorderPinned`. |
| `Buoy/Models/NoteStore.swift` | `notes` (createdAt asc), `togglePin`, `reorderPinnedNotes(_ orderedIDs:)`, `loadNoteList`, migrations v1..v7. |
| `Buoy/Models/Note.swift` | `isPinned`, `pinnedOrder: Int64?`. |
| `Buoy/Helpers/PanelLayoutMetrics.swift` | `overlayHorizontalInset = 8`, `allNotesTopInset = 43`, `allNotesBottomInset = 43`, `minimumContentWidth` ≈ 292. |

Ordering today: pinned band first (by `pinnedOrder`, then `createdAt`, then
`id`), then unpinned by `createdAt` asc. Computed in `AllNotesPanel.filteredNotes`.

### Why it feels finicky (the audit)

1. **Two drag sources on one row.** `NoteRowDragHandle` is a custom `NSView`
   placed under the *title text only*; it runs a modal `nextEvent` loop, lifts
   the row after a 0.16 s hold (CA scale 1.015 + shadow + backgroundColor),
   builds a card snapshot, dims the source row to alpha 0.28, and starts an
   `NSDraggingSession`. Separately, `pasteboardWriterForRow` enables
   `NSTableView`'s *built-in* row drag, which fires when the press lands on row
   padding or beside the title. No hold, no lift, AppKit's flat default drag
   image. Which one the user gets depends on the pixel they grab.
2. **Double snap on drop.** `acceptDrop` calls `reloadData()` (not
   `moveRow(at:to:)`), then `onReorderPinned` → `NoteStore.loadNoteList` →
   SwiftUI re-render → `updateNSView` → a second `reloadData()`. The `.gap`
   feedback animates, then the table snaps twice.
3. **No slide-back on cancel.** `animatesToStartingPositionsOnCancelOrFail = false`.
4. **Slow click flashes a lift.** Holding 0.16 s without moving lifts the row;
   releasing still selects.
5. **Split click handling.** Drag handle forwards clicks via its own loop; the
   rest of the row uses SwiftUI `onTapGesture`. The modal loop freezes SwiftUI
   hover animations while pressed.
6. **Only pinned rows drag**, only inside the pinned band, and never during
   search. All three failures are silent (cursor shows "not allowed" or nothing).
7. `updateNSView` reloads on every SwiftUI evaluation; its if/else is dead code.
   Cell reuse via `makeView(withIdentifier:)` lets hover `@State` hop rows.
8. `rowHeight = 30` is hard-coded with `rowSizeStyle = .custom`.
9. Trailing swipe row action (`rowActionsForRow`) is a third gesture, mostly
   eaten by the hosting view.

---

## Decisions (do not re-litigate)

| Question | Decision |
|---|---|
| Nesting | One level. Folders hold notes only. |
| Sections | Three, with a divider between each: **Pinned**, **Folders**, **All Notes**. |
| Membership | A note is in at most one folder (`notes.folderID`). |
| Visibility | A filed note **still appears in All Notes**. A pinned + filed note appears in all three sections. Pin icon shows everywhere. |
| Ordering | Pinned: manual (existing `pinnedOrder`). Folder rows: manual. Notes inside a folder: manual (`folderOrder`). All Notes: `createdAt` asc, **never reorderable**. |
| Add / remove | Drag a note row from Pinned or All Notes **onto** a folder row to file it. Drag a folder child **out** into the All Notes section to unfile it. No context menu. |
| Create folder | "New folder" button in the panel header, beside the close button. New folder appears expanded with its name in inline edit. |
| Rename / delete | Hover buttons on the folder row, same pattern as the pin/x on note rows: pencil = inline rename, x = delete folder. Deleting a folder **unfiles** its notes (never deletes notes). Goes through a confirm dialog. |
| Disclosure | Collapsed by default. `isExpanded` persisted per folder. |
| Search | Flatten to one list of matching notes, no sections, no drag, exactly like today. |
| Scope | Panel only. Header, ⌘←/→, Harbor pill, footer counts, search matching are untouched. |
| Sizing | Widen the panel from 214 pt to the window content width minus `2 × overlayHorizontalInset`. Keep the 300 pt list cap. Window size does not change. |
| Container | `NSOutlineView`, one drag source, animated `moveItem` commits. |

Out of scope: nested folders, multi-folder membership, folder chip in the
header, folder-scoped navigation, folder names in search, drag onto the editor.

---

## Phase 1: NSOutlineView with one drag model (no folders)

Goal: identical feature surface to today, but one consistent drag and drop
feel. Pinned reorder still works; nothing else is draggable yet.

### 1.1 Replace `NotesTableViewWrapper` with `NotesOutlineViewWrapper`

In `Buoy/Views/AppKitWrappers.swift`:

- Delete `NoteRowDragHandle` (the whole `NSViewRepresentable` and
  `DragHandleNSView`) and remove `dragNoteID` from `NoteRow` in
  `AllNotesPanel.swift`. The row's title area becomes plain SwiftUI again.
- Delete the `rowActionsForRow` swipe action.
- New `NotesOutlineViewWrapper: NSViewRepresentable` returning an
  `NSScrollView` whose `documentView` is an `NSOutlineView`. Configure like the
  current table: `headerView = nil`, `backgroundColor = .clear`,
  `intercellSpacing = .zero`, `gridStyleMask = []`, `style = .plain`,
  `selectionHighlightStyle = .none`, `indentationPerLevel = 0` in Phase 1,
  `indentationMarkerFollowsCell = false`, one column,
  `registerForDraggedTypes([noteRowPasteboardType])`,
  `setDraggingSourceOperationMask(.move, forLocal: true)`,
  `draggingDestinationFeedbackStyle = .gap`.
- Keep `noteRowPasteboardType = "GabeMempin.Buoy.note-row"`.

### 1.2 Item model

Introduce a small enum the coordinator holds as its tree so Phase 2 can add
cases without restructuring:

```swift
enum AllNotesItem: Hashable {
    case note(id: String, section: Section)
    case folder(id: String)          // unused in Phase 1
    case divider(Section)            // unused in Phase 1
    enum Section: Hashable { case pinned, folders, allNotes }
}
```

Phase 1 tree is flat: pinned notes as `.note(id, .pinned)` then unpinned as
`.note(id, .allNotes)`, in the same order `AllNotesPanel.filteredNotes`
produces today. Keep a `[String: Note]` lookup in the coordinator.

The outline's data source uses these `AllNotesItem` values as items. Items
must be reference-stable for `NSOutlineView` expansion/animation to work, so
either box them in a `final class` or keep `NSObject` wrappers cached by id.
Boxing in a class keyed by id in a dictionary is the simplest.

### 1.3 Cells

`outlineView(_:viewFor:item:)` returns an `NSHostingView<AnyView>` hosting the
existing `NoteRow`, exactly as `tableView(_:viewFor:row:)` does today. Keep
`NoSeparatorRowView` for `rowViewForItem`.

Per-item heights via `outlineView(_:heightOfRowByItem:)`: note rows 30. Do not
set a global `rowHeight`.

Fix the hover-state hop: give the hosting view's root a stable identity,
`.id(note.id)` on the `NoteRow`, so cell reuse does not carry `isHovering`
across notes.

### 1.4 One drag source

- `outlineView(_:pasteboardWriterForItem:)`: return an `NSPasteboardItem`
  carrying the note id when the item is a pinned note and search is empty;
  otherwise `nil`. This is the **only** place a drag can start.
- `outlineView(_:draggingSession:willBeginAt:forItems:)`: this is where the
  drag image is supplied. Port `liftedImage(for:)` from the deleted handle
  (card with 7 pt radius, `windowBackgroundColor` at 0.96, shadow 0.16 / blur 6
  / offset (0, -1), 8 pt padding) and call
  `session.enumerateDraggingItems(...)` to set each item's
  `setDraggingFrame(_:contents:)` to that image over the row's frame. Dim the
  source row view to alpha 0.28 here (animated 0.08 s).
- Drop the 0.16 s hold and the CA scale/shadow "lift" on the source row. The
  drag image *is* the lift. If a lift is wanted later, it is one
  `NSAnimationContext` block in `willBeginAt`, not a modal event loop.
- `outlineView(_:draggingSession:endedAt:operation:)`: restore alpha to 1
  (0.12 s). Leave `animatesToStartingPositionsOnCancelOrFail` at its default
  (true) so a cancelled drag slides back.
- Route both durations through `BuoyMotion.duration(_:)`.

### 1.5 Drop validation and commit (Phase 1 rules)

`outlineView(_:validateDrop:proposedItem:proposedChildIndex:)`:

- Reject unless search is empty and the pasteboard carries a note id.
- Reject unless the dragged note is pinned.
- Accept only `proposedItem == nil` (top level) with a child index in
  `0...pinnedCount`. Call `setDropItem(nil, dropChildIndex: idx)` to pin the
  gap position, return `.move`.
- Everything else returns `[]`.

`outlineView(_:acceptDrop:item:childIndex:)`:

1. Compute source index and destination index exactly as `acceptDrop` does
   today (decrement destination when moving down).
2. Mutate the coordinator's tree first.
3. Animate: `outlineView.beginUpdates()`,
   `moveItem(at: src, inParent: nil, to: dst, inParent: nil)`, `endUpdates()`.
4. Persist: `parent.onReorderPinned(orderedPinnedIDs)`.
5. Return `true`.

No `reloadData()` in this path.

### 1.6 `updateNSView` diffs instead of reloading

Compute the new flat tree from `notes`. If the sequence of item ids is
unchanged, do **not** call `reloadData()`; instead call
`reloadItem(_:reloadChildren: false)` only for items whose `Note` changed
(title, `isPinned`, active id). If the id sequence changed (insert, delete,
pin toggle moves a row across sections), fall back to `reloadData()` for now.
Phase 2 can upgrade this to insert/remove animations.

Store the last `currentNoteID` in the coordinator; when it changes, reload the
old and new active items only.

### 1.7 Panel width

In `AllNotesPanel.swift`, replace `.frame(width: 214)` with
`.frame(maxWidth: .infinity)` and have `ContentView` pass the width: inside the
existing `GeometryReader`, apply
`.frame(width: proxy.size.width - 2 * PanelLayoutMetrics.overlayHorizontalInset)`
to `AllNotesPanel`. The panel keeps `.padding(.trailing, overlayHorizontalInset)`.
Verify at the minimum window width the panel does not overlap the traffic
lights (the header is 43 pt above it; top inset already handles this).

Add `static let allNotesListMaxHeight: CGFloat = 300` to `PanelLayoutMetrics`
and use it in place of the two literal `300`s.

### 1.8 `ContentView` type-check budget

`ContentView.body` is at the type-checker limit (see `CLAUDE.md`). The width
frame above is one modifier on an existing view and should be fine, but if the
build starts timing out on `ContentView.swift`, move the whole
`GeometryReader { ... AllNotesPanel ... }` block into an extracted
`AllNotesOverlay` subview that takes the bindings and closures. Verify with
`xcodebuild`, not the IDE.

### 1.9 Phase 1 acceptance

- Pressing anywhere on a pinned row and moving 3+ pt starts one drag with the
  card image; there is no hold delay and no second flat-image drag path.
- Releasing over the pinned band moves the row with a single animation. No
  snap after the gap closes.
- Releasing outside the band slides the card back to its row.
- A click (press and release without moving) on any part of a row selects it,
  with no lift flash, regardless of how long the press is held.
- Hover pin/x buttons still work and never carry over to another row after a
  reorder or reload.
- Reduce Motion: drag image still appears, dim/restore are instantaneous.
- No `NoteRowDragHandle`, no `rowActionsForRow`, no `reloadData` inside
  `acceptDrop`.

---

## Phase 2: Folders

### 2.1 Schema: migration `v8_folders` in `NoteStore.swift`

Register after `v7_autoTitleRestage`, following the existing style (column
existence checks, raw SQL where it is clearer):

```sql
CREATE TABLE IF NOT EXISTS folders (
    id         TEXT PRIMARY KEY NOT NULL,
    name       TEXT NOT NULL,
    sortOrder  INTEGER NOT NULL,
    isExpanded INTEGER NOT NULL DEFAULT 0,
    createdAt  INTEGER NOT NULL
);
ALTER TABLE notes ADD COLUMN folderID TEXT;      -- nullable, no FK
ALTER TABLE notes ADD COLUMN folderOrder INTEGER; -- nullable
```

No foreign key on purpose: deleting a folder is a single
`UPDATE notes SET folderID = NULL, folderOrder = NULL WHERE folderID = ?`.

### 2.2 Models

- New `Buoy/Models/Folder.swift`: `struct Folder: Identifiable, Codable,
  FetchableRecord, PersistableRecord` with `id`, `name`, `sortOrder: Int64`,
  `isExpanded: Bool`, `createdAt: Int64`, `databaseTableName = "folders"`.
  Ids: `Note.newID()` style timestamp string.
- `Note`: add `var folderID: String?` and `var folderOrder: Int64?`; add both
  to `Columns`. Update `createNote(titled:)` to pass `nil` for both.

### 2.3 `NoteStore` API

All follow the `togglePin` / `reorderPinnedNotes` pattern: `db.write`, then
`loadNoteList()`, then patch `currentNote` if affected, `print` on error.

- `var folders: [Folder]` loaded in `loadNoteList()` ordered by `sortOrder`.
- `createFolder(named:) -> Folder` (sortOrder = max + 1, `isExpanded = true`).
- `renameFolder(_ id: String, to name: String)`.
- `deleteFolder(_ id: String)`: unfile children, delete row, renumber
  `sortOrder` of the rest.
- `setFolderExpanded(_ id: String, _ expanded: Bool)`: DB write only, no
  `loadNoteList` (avoid a SwiftUI re-render on every disclosure click; the
  outline already animated it).
- `reorderFolders(_ orderedIDs: [String])`: same guard shape as
  `reorderPinnedNotes` (count and set equality), writes `sortOrder`.
- `fileNote(_ noteID: String, inFolder folderID: String, at index: Int?)`:
  sets `folderID`, assigns `folderOrder` (append when `index == nil`),
  renumbers the folder's other children. Filing a note already in another
  folder moves it.
- `unfileNote(_ noteID: String)`: clears both columns, renumbers the old
  folder's children.
- `reorderNotes(inFolder folderID: String, orderedIDs: [String])`.

Pinning and filing are independent. `togglePin` must not touch `folderID`.
`deleteNote`/`discardNote` need no change (the row goes away; folder counts are
derived).

### 2.4 Tree shape

`NotesOutlineViewWrapper` gains `folders: [Folder]` and builds:

```
.note(id, .pinned)         × pinned notes, by pinnedOrder
.divider(.folders)         (only if there is at least one folder)
.folder(id)                × folders, by sortOrder
    .note(id, .folder)     × children, by folderOrder   (expandable)
.divider(.allNotes)        (only if pinned or folders rendered above)
.note(id, .allNotes)       × every note, by createdAt asc
```

Empty pinned band: no Pinned rows and no divider. Empty folder: shows the
folder row with no disclosure children (still expandable, shows nothing).

`isItemExpandable` true only for `.folder`. On first display apply
`Folder.isExpanded` via `expandItem`/`collapseItem` with animation disabled.
Implement `outlineViewItemDidExpand`/`DidCollapse` to call
`setFolderExpanded`.

Row heights: note 30, folder 28, divider 9. Divider cell is a 1 pt
`separatorColor` line inset 10 pt horizontally, not selectable, not
draggable, `outlineView(_:shouldSelectItem:)` returns false for it.

Set `indentationPerLevel = 14` so folder children indent. Keep the disclosure
triangle: `outlineView(_:shouldShowOutlineCellForItem:)` true for folders only.
Because `NoteRow` and `FolderRow` are SwiftUI inside `NSHostingView`, the
outline cell (triangle) is AppKit's own; keep `indentationMarkerFollowsCell =
true` so it sits at the folder row's left edge.

### 2.5 Views

- `FolderRow` (new, in `AllNotesPanel.swift`): folder SF Symbol
  (`folder` / `folder.fill` when expanded), name (or `TextField` when
  renaming), child count in `.tertiary`, hover buttons: pencil
  (`pencil`, "Rename folder") and x (`xmark`, "Delete folder"). Same 18 pt
  circle button style, `.pointingHandCursor()`, `.accessibilityLabel` on every
  button, `.accessibilityAddTraits(.isButton)` on the row. Inline rename: a
  borderless `TextField` with `focusRingType` none (use a small
  `NSViewRepresentable` around `NSTextField` like `SearchFieldWrapper` if
  SwiftUI's field cannot take focus in the non-activating panel; commit on
  Return or focus loss, cancel on Escape, empty name reverts).
- `AllNotesPanel` header: add a `folder.badge.plus` button before the close
  button, `accessibilityLabel("New folder")`, `.help("New folder")`. On tap:
  `onCreateFolder()`; the panel then puts the new folder id into a
  `@State renamingFolderID` that the wrapper passes down so the row mounts in
  edit mode.
- `NoteRow` unchanged apart from the Phase 1 `.id`.
- Search: when `searchText` is non-empty, pass `folders: []` and the flat
  filtered notes; the wrapper renders the Phase 1 flat tree and disables drag.

### 2.6 Drag rules (final)

`pasteboardWriterForItem` returns a writer for:

- `.note(_, .pinned)`, `.note(_, .folder)`, `.note(_, .allNotes)`
  (All Notes rows are draggable only so they can be dropped onto folders).
- `.folder(id)` with a second pasteboard type
  `"GabeMempin.Buoy.folder-row"`.
- Never for `.divider`. Never while searching.

`validateDrop(proposedItem:proposedChildIndex:)`:

| Dragged | Drop target | Result |
|---|---|---|
| pinned note | top level, index inside pinned band | reorder pinned (`.move`, `.above`) |
| any note | **on** a `.folder` row (`childIndex == NSOutlineViewDropOnItemIndex`) | file into that folder (append). Highlight the folder row via `setDropItem(folder, dropChildIndex: NSOutlineViewDropOnItemIndex)`. |
| folder child | between children of the **same** folder | reorder in folder |
| folder child | between children of a **different** folder, or on it | move to that folder at that index |
| folder child | top level, index inside the All Notes section | unfile (`.move`; use `.gap` at the All Notes divider position, then the row appears at its chronological spot) |
| folder | top level, index inside the folders band | reorder folders |
| All Notes note | anywhere that is not a folder | reject `[]` |
| anything | on a divider, or a note row (`dropOn`) | reject `[]` |

Rule: a note dragged from All Notes onto a folder is *added* (it stays in All
Notes). A note dragged out of a folder to All Notes is *removed* from the
folder. Pinned status never changes via drag.

`acceptDrop`: mutate tree, animate with `moveItem` / `insertItems` /
`removeItems` inside `beginUpdates`/`endUpdates`, then call the matching
`NoteStore` method. Filing from All Notes is an *insert* into the folder
(the All Notes row stays); unfiling is a *remove* from the folder (the All
Notes row already exists). Expanding a collapsed target folder on drop is
optional; do not auto-expand during hover.

### 2.7 `updateNSView` with folders

Extend the Phase 1 diff: compare the flattened id sequence *including* folder
ids and dividers. When only a note's fields changed, `reloadItem`. When the
structure changed and the change is not one the drop handler already animated,
`reloadData()` and re-apply expansion state from `Folder.isExpanded`.

### 2.8 Delete folder confirm

Reuse the visual style of `DeleteConfirmDialog` but with different copy.
Either generalise it (`title`, `message`, `confirmLabel` parameters) or add a
`FolderDeleteConfirmDialog`. Copy: "Delete “{name}”?" / "Its {n} notes stay in
All Notes." Confirm button "Delete Folder". Wire through `ContentView` the same
way `pendingDeleteNote` is: a `@State pendingDeleteFolder: Folder?`, included in
the blur condition and the `isTransientUIVisible`-style guards next to
`pendingDeleteNote`.

Watch the `ContentView.body` budget: add the new `@State` and the overlay in
the extracted `AllNotesOverlay` subview from 1.8 if not already extracted.

### 2.9 Phase 2 acceptance

- Fresh DB and an existing DB both open; existing pins and order unchanged.
- New folder appears expanded, in rename mode, under a divider; Escape with an
  empty name removes it.
- Drag a note from All Notes onto a folder: folder count increments, the note
  is still listed in All Notes, and it appears in the folder if expanded.
- Drag that child back into the All Notes section: it leaves the folder; All
  Notes is unchanged.
- Pinned + filed note appears in Pinned, in its folder, and in All Notes, with
  the pin icon in all three.
- Reordering works in Pinned, among folders, and within a folder. All Notes
  rows cannot be reordered (drop rejected with the slide-back).
- Collapse state survives quit and relaunch.
- Delete folder: confirm dialog, notes remain, folder gone.
- Search: flat list, no dividers, no folders, no drag.
- Panel is wider than 214 pt and never overlaps the traffic lights at
  minimum window width.
- VoiceOver: every new button has a label; folder rows announce name and
  count; dividers are not focusable.

---

## Gotchas carried over from `CLAUDE.md`

- Never decode RTF in a view body; keep `NotePlainText.of(note)` for search.
- Every movement animation goes through `BuoyMotion.*`; AppKit durations
  through `BuoyMotion.duration(_:)`.
- Use `Color.buoy*` tokens, `BuoyFont` roles, `.pointingHandCursor()` and
  `.accessibilityLabel` on every clickable control.
- `ContentView.body` is at the type-checker limit: add UI as extracted
  subviews and verify with `xcodebuild`, not the IDE.
- No focus rings on borderless fields.
- Do not run builds or launch the app after routine changes unless asked; the
  user launches manually via `./script/build_and_run.sh`.
- Commits: no Claude attribution lines.
