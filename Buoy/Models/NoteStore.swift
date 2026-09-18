import Foundation
import GRDB
import Observation

enum NavigationDirection {
    case forward
    case backward
}

@Observable
final class NoteStore {
    var notes: [Note] = []
    /// One-level note folders, ordered by `sortOrder`. Purely an All Notes
    /// panel concern — nothing else in the app reads this.
    var folders: [Folder] = []
    var currentNote: Note?
    var lastNavigationDirection: NavigationDirection?
    /// Set the instant an auto-generated title lands on the current note, so
    /// the header can play the reveal animation. The header clears it back to
    /// `nil` once the animation finishes.
    var titleReveal: TitleReveal?
    /// The id of the note an auto-title request is currently running for, so
    /// the header can play a "thinking" shimmer over its title. `NoteAutoTitler`
    /// only ever runs one request at a time, so a single id is enough.
    var titleThinking: String?

    struct TitleReveal: Equatable {
        let id = UUID()
        let noteID: String
        let title: String
    }

    private var db: DatabaseQueue?
    private var saveContentWork: DispatchWorkItem?
    private var saveTitleWork: DispatchWorkItem?
    // `@Observable`'s synthesized accessors can't wrap a `lazy var`, and none
    // of these are values a SwiftUI view should ever bind to.
    @ObservationIgnored private lazy var autoTitler = NoteAutoTitler(store: self)
    /// Mirrors `AppSettings.autoTitleEnabled`. NoteStore has no settings
    /// reference of its own, so it tracks the flag via the same
    /// `.settingsDidChange` broadcast `SettingsPanel` triggers on every save.
    @ObservationIgnored private var autoTitleEnabled = AppSettings.load().autoTitleEnabled
    @ObservationIgnored private var settingsObserver: NSObjectProtocol?

    init() {
        setupDatabase()
        loadNoteList()
        if let first = notes.first {
            switchNote(to: first)
        } else {
            createNote()
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let enabled = AppSettings.load().autoTitleEnabled
            self.autoTitleEnabled = enabled
            if !enabled {
                // A pending debounce or an in-flight request must not land
                // after the user has turned the feature off.
                self.autoTitler.cancelAll()
            }
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    // MARK: - Database Setup

    private func setupDatabase() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".buoy")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("notes.db").path

        guard let queue = try? DatabaseQueue(path: dbPath) else {
            print("[NoteStore] Failed to open database at \(dbPath)")
            return
        }
        db = queue
        runMigrations()
        NoteStore_Migration.migrateHTMLtoRTF(in: queue)
    }

    private func runMigrations() {
        guard let db else { return }
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS notes (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL DEFAULT '',
                    content TEXT NOT NULL DEFAULT '',
                    createdAt INTEGER NOT NULL,
                    updatedAt INTEGER NOT NULL
                )
            """)
        }

        migrator.registerMigration("v2_contentRTF") { db in
            let columns = try db.columns(in: "notes").map { $0.name }
            if !columns.contains("contentRTF") {
                try db.alter(table: "notes") { t in
                    t.add(column: "contentRTF", .blob).defaults(to: Data())
                }
            }
        }

        migrator.registerMigration("v3_isPinned") { db in
            let columns = try db.columns(in: "notes").map { $0.name }
            if !columns.contains("isPinned") {
                try db.alter(table: "notes") { t in
                    t.add(column: "isPinned", .boolean).defaults(to: false)
                }
            }
        }

        migrator.registerMigration("v4_pinnedOrder") { db in
            let columns = try db.columns(in: "notes").map { $0.name }
            if !columns.contains("pinnedOrder") {
                try db.alter(table: "notes") { t in
                    t.add(column: "pinnedOrder", .integer)
                }
            }

            var nextOrder = (try Int64.fetchOne(
                db,
                sql: "SELECT MAX(pinnedOrder) FROM notes WHERE isPinned = 1"
            ) ?? -1) + 1
            let unorderedPinnedIDs = try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM notes
                    WHERE isPinned = 1 AND pinnedOrder IS NULL
                    ORDER BY createdAt ASC, id ASC
                """
            )
            for id in unorderedPinnedIDs {
                try db.execute(
                    sql: "UPDATE notes SET pinnedOrder = ? WHERE id = ?",
                    arguments: [nextOrder, id]
                )
                nextOrder += 1
            }
        }

        migrator.registerMigration("v5_autoTitlePending") { db in
            let columns = try db.columns(in: "notes").map { $0.name }
            if !columns.contains("autoTitlePending") {
                try db.alter(table: "notes") { t in
                    t.add(column: "autoTitlePending", .boolean).defaults(to: false)
                }
            }
        }

        // Replaces the single `autoTitlePending` flag with a two-stage model
        // (name at 50 chars, refine at 300) plus enough state to restore the
        // original "Note N" if the note's text is cleared back to empty.
        migrator.registerMigration("v6_autoTitleStages") { db in
            let columns = try db.columns(in: "notes").map { $0.name }
            if !columns.contains("autoTitleStage") {
                try db.alter(table: "notes") { t in
                    t.add(column: "autoTitleStage", .integer).defaults(to: 0)
                }
            }
            if !columns.contains("autoTitleLocked") {
                try db.alter(table: "notes") { t in
                    // Existing rows (pre-upgrade, or already pending under v5)
                    // default locked — auto-titling only ever targets notes
                    // created from this point on.
                    t.add(column: "autoTitleLocked", .boolean).defaults(to: true)
                }
            }
            if !columns.contains("autoTitleDefaultTitle") {
                try db.alter(table: "notes") { t in
                    t.add(column: "autoTitleDefaultTitle", .text)
                }
            }
            if columns.contains("autoTitlePending") {
                try db.execute(sql: "UPDATE notes SET autoTitleLocked = NOT autoTitlePending")
                try db.alter(table: "notes") { t in
                    t.drop(column: "autoTitlePending")
                }
            }
        }

        // `NoteAutoTitler.thresholds` grew from [50, 300] to [50, 100, 500],
        // which moves the "finished" mark from stage 2 to stage 3. Rows that
        // had already spent both of the old stages are done and must stay
        // done — without this they'd read as eligible again and rename
        // themselves on the owner's next keystroke. Rows at stage 1 are left
        // alone: they legitimately still have refinements ahead of them.
        migrator.registerMigration("v7_autoTitleRestage") { db in
            try db.execute(sql: "UPDATE notes SET autoTitleStage = 3 WHERE autoTitleStage >= 2")
        }

        // One-level note folders. `notes.folderID` deliberately carries no
        // foreign key: deleting a folder must leave its notes alone, which is
        // then a single UPDATE rather than a cascade to reason about.
        migrator.registerMigration("v8_folders") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS folders (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    sortOrder INTEGER NOT NULL,
                    isExpanded INTEGER NOT NULL DEFAULT 0,
                    createdAt INTEGER NOT NULL
                )
            """)

            let columns = try db.columns(in: "notes").map { $0.name }
            if !columns.contains("folderID") {
                try db.alter(table: "notes") { t in
                    t.add(column: "folderID", .text)
                }
            }
            if !columns.contains("folderOrder") {
                try db.alter(table: "notes") { t in
                    t.add(column: "folderOrder", .integer)
                }
            }
        }

        // Manual order for the All Notes list. Seeded from the existing
        // createdAt order, so the list looks identical until the first drag.
        migrator.registerMigration("v9_noteSortOrder") { db in
            let columns = try db.columns(in: "notes").map { $0.name }
            if !columns.contains("sortOrder") {
                try db.alter(table: "notes") { t in
                    t.add(column: "sortOrder", .integer)
                }
            }
            let ordered = try String.fetchAll(
                db,
                sql: "SELECT id FROM notes ORDER BY createdAt ASC, id ASC"
            )
            for (index, id) in ordered.enumerated() {
                try db.execute(
                    sql: "UPDATE notes SET sortOrder = ? WHERE id = ?",
                    arguments: [Int64(index), id]
                )
            }
        }

        try? migrator.migrate(db)
    }

    // MARK: - CRUD

    func loadNoteList() {
        guard let db else { return }
        notes = (try? db.read { db in
            try Note
                .order(
                    Note.Columns.sortOrder.asc,
                    Note.Columns.createdAt.asc,
                    Note.Columns.id.asc
                )
                .fetchAll(db)
        }) ?? []
        folders = (try? db.read { db in
            try Folder
                .order(Folder.Columns.sortOrder.asc)
                .fetchAll(db)
        }) ?? []
    }

    func switchNote(to note: Note) {
        flushPendingSaves()
        titleReveal = nil
        titleThinking = nil

        guard let db else { return }
        currentNote = (try? db.read { db in
            try Note.fetchOne(db, key: note.id)
        })
    }

    func restoreSelection(noteID: String?) {
        guard let noteID,
              let note = notes.first(where: { $0.id == noteID })
        else { return }
        switchNote(to: note)
    }

    /// Creates a note and makes it current.
    ///
    /// - Parameter title: an explicit title, or `nil` for the next "Note N".
    ///   Passing one writes it with the insert rather than through the debounced
    ///   `saveTitle` path, which matters for short-lived notes: a title still in
    ///   flight when the note is discarded is a write aimed at a row that no
    ///   longer exists. It also keeps scratch notes from consuming a number in
    ///   the "Note N" sequence.
    func createNote(titled title: String? = nil) {
        // Commit any in-flight edits against the *outgoing* note before we
        // repoint currentNote, so a debounced save can't land on the new note.
        flushPendingSaves()
        titleReveal = nil
        titleThinking = nil

        guard let db else { return }
        let now = Note.currentTimestamp()
        let defaultTitle = title ?? "Note \(notes.count + 1)"
        let newNote = Note(
            id: Note.newID(),
            title: defaultTitle,
            contentRTF: Data(),
            createdAt: now,
            updatedAt: now,
            isPinned: false,
            pinnedOrder: nil,
            autoTitleStage: 0,
            // Only notes created with no explicit title (i.e. not scratch
            // notes like the bug report) are eligible for auto-naming.
            autoTitleLocked: title != nil,
            autoTitleDefaultTitle: defaultTitle,
            folderID: nil,
            folderOrder: nil,
            sortOrder: nextNoteSortOrder()
        )
        _ = try? db.write { db in
            try newNote.insert(db)
        }
        loadNoteList()
        currentNote = newNote
    }

    private func nextNoteSortOrder() -> Int64 {
        guard let db else { return 0 }
        let maximum = (try? db.read { db in
            try Int64.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM notes")
        }) ?? nil
        return (maximum ?? -1) + 1
    }

    /// Manual order for the All Notes list.
    func reorderNotes(_ orderedIDs: [String]) {
        let currentIDs = notes.map(\.id)
        guard orderedIDs.count == currentIDs.count,
              Set(orderedIDs) == Set(currentIDs),
              let db
        else { return }

        do {
            try db.write { db in
                for (index, id) in orderedIDs.enumerated() {
                    try db.execute(
                        sql: "UPDATE notes SET sortOrder = ? WHERE id = ?",
                        arguments: [Int64(index), id]
                    )
                }
            }
            loadNoteList()
        } catch {
            print("[NoteStore] Failed to reorder notes: \(error)")
        }
    }

    func togglePin(_ note: Note) {
        guard let db else { return }
        let newValue = !note.isPinned
        do {
            let newOrder: Int64? = try db.write { db -> Int64? in
                if newValue {
                    let nextOrder = (try Int64.fetchOne(
                        db,
                        sql: "SELECT MAX(pinnedOrder) FROM notes WHERE isPinned = 1"
                    ) ?? -1) + 1
                    try db.execute(
                        sql: "UPDATE notes SET isPinned = 1, pinnedOrder = ? WHERE id = ?",
                        arguments: [nextOrder, note.id]
                    )
                    return nextOrder
                }

                try db.execute(
                    sql: "UPDATE notes SET isPinned = 0, pinnedOrder = NULL WHERE id = ?",
                    arguments: [note.id]
                )
                return nil
            }
            loadNoteList()
            if currentNote?.id == note.id {
                currentNote?.isPinned = newValue
                currentNote?.pinnedOrder = newOrder
            }
        } catch {
            print("[NoteStore] Failed to toggle note pin: \(error)")
        }
    }

    func reorderPinnedNotes(_ orderedIDs: [String]) {
        let currentPinnedIDs = notes.filter(\.isPinned).map(\.id)
        guard orderedIDs.count == currentPinnedIDs.count,
              Set(orderedIDs) == Set(currentPinnedIDs),
              let db
        else { return }

        do {
            try db.write { db in
                for (index, id) in orderedIDs.enumerated() {
                    try db.execute(
                        sql: "UPDATE notes SET pinnedOrder = ? WHERE id = ? AND isPinned = 1",
                        arguments: [Int64(index), id]
                    )
                }
            }
            loadNoteList()
            if let currentID = currentNote?.id,
               let index = orderedIDs.firstIndex(of: currentID) {
                currentNote?.pinnedOrder = Int64(index)
            }
        } catch {
            print("[NoteStore] Failed to reorder pinned notes: \(error)")
        }
    }

    // MARK: - Folders

    /// Notes filed in `folderID`, in their manual order. `folderOrder` is kept
    /// contiguous by every mutator below, so the secondary sorts only matter
    /// for rows written before a renumber landed.
    func notesInFolder(_ folderID: String) -> [Note] {
        notes
            .filter { $0.folderID == folderID }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.folderOrder ?? Int64.max
                let rhsOrder = rhs.folderOrder ?? Int64.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id < rhs.id
            }
    }

    @discardableResult
    func createFolder(named name: String = Folder.defaultName) -> Folder? {
        guard let db else { return nil }
        do {
            let nextOrder = (try db.read { db in
                try Int64.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM folders")
            } ?? -1) + 1
            let folder = Folder(
                id: Folder.newID(),
                name: name,
                sortOrder: nextOrder,
                // Expanded so the inline rename field lands in view.
                isExpanded: true,
                createdAt: Note.currentTimestamp()
            )
            try db.write { db in
                try folder.insert(db)
            }
            loadNoteList()
            return folder
        } catch {
            print("[NoteStore] Failed to create folder: \(error)")
            return nil
        }
    }

    func renameFolder(_ folderID: String, to name: String) {
        guard let db else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? Folder.defaultName : trimmed
        do {
            try db.write { db in
                try db.execute(
                    sql: "UPDATE folders SET name = ? WHERE id = ?",
                    arguments: [resolved, folderID]
                )
            }
            loadNoteList()
        } catch {
            print("[NoteStore] Failed to rename folder: \(error)")
        }
    }

    /// Deletes the folder row and unfiles its notes. Never deletes a note —
    /// every note is still listed in the All Notes section.
    func deleteFolder(_ folderID: String) {
        guard let db else { return }
        do {
            try db.write { db in
                try db.execute(
                    sql: "UPDATE notes SET folderID = NULL, folderOrder = NULL WHERE folderID = ?",
                    arguments: [folderID]
                )
                try db.execute(sql: "DELETE FROM folders WHERE id = ?", arguments: [folderID])

                let remaining = try String.fetchAll(
                    db,
                    sql: "SELECT id FROM folders ORDER BY sortOrder ASC, createdAt ASC"
                )
                for (index, id) in remaining.enumerated() {
                    try db.execute(
                        sql: "UPDATE folders SET sortOrder = ? WHERE id = ?",
                        arguments: [Int64(index), id]
                    )
                }
            }
            loadNoteList()
            if currentNote?.folderID == folderID {
                currentNote?.folderID = nil
                currentNote?.folderOrder = nil
            }
        } catch {
            print("[NoteStore] Failed to delete folder: \(error)")
        }
    }

    /// Disclosure state only. Deliberately does **not** call `loadNoteList`:
    /// the outline view has already animated the expansion, so re-reading every
    /// note and folder back out of SQLite on each disclosure click would be
    /// pure waste. (The in-memory `folders` write below is still observed, so
    /// SwiftUI does re-render — it just costs nothing and repaints one row.)
    func setFolderExpanded(_ folderID: String, _ expanded: Bool) {
        guard let db else { return }
        guard let index = folders.firstIndex(where: { $0.id == folderID }),
              folders[index].isExpanded != expanded
        else { return }
        folders[index].isExpanded = expanded
        do {
            try db.write { db in
                try db.execute(
                    sql: "UPDATE folders SET isExpanded = ? WHERE id = ?",
                    arguments: [expanded, folderID]
                )
            }
        } catch {
            print("[NoteStore] Failed to persist folder expansion: \(error)")
        }
    }

    func reorderFolders(_ orderedIDs: [String]) {
        let currentIDs = folders.map(\.id)
        guard orderedIDs.count == currentIDs.count,
              Set(orderedIDs) == Set(currentIDs),
              let db
        else { return }

        do {
            try db.write { db in
                for (index, id) in orderedIDs.enumerated() {
                    try db.execute(
                        sql: "UPDATE folders SET sortOrder = ? WHERE id = ?",
                        arguments: [Int64(index), id]
                    )
                }
            }
            loadNoteList()
        } catch {
            print("[NoteStore] Failed to reorder folders: \(error)")
        }
    }

    /// Files `noteID` into `folderID` at `index` (appended when `nil`).
    /// Moving a note that is already filed elsewhere renumbers the folder it
    /// left. Pin state is never touched — pinning and filing are independent.
    func fileNote(_ noteID: String, inFolder folderID: String, at index: Int?) {
        guard let db,
              folders.contains(where: { $0.id == folderID }),
              let note = notes.first(where: { $0.id == noteID })
        else { return }

        let previousFolderID = note.folderID
        var ordered = notesInFolder(folderID).map(\.id).filter { $0 != noteID }
        let insertIndex = min(max(index ?? ordered.count, 0), ordered.count)
        ordered.insert(noteID, at: insertIndex)

        do {
            try db.write { db in
                try db.execute(
                    sql: "UPDATE notes SET folderID = ? WHERE id = ?",
                    arguments: [folderID, noteID]
                )
                for (position, id) in ordered.enumerated() {
                    try db.execute(
                        sql: "UPDATE notes SET folderOrder = ? WHERE id = ?",
                        arguments: [Int64(position), id]
                    )
                }
                if let previousFolderID, previousFolderID != folderID {
                    try Self.renumberFolderContents(previousFolderID, in: db)
                }
            }
            loadNoteList()
            if currentNote?.id == noteID {
                currentNote?.folderID = folderID
                currentNote?.folderOrder = Int64(insertIndex)
            }
        } catch {
            print("[NoteStore] Failed to file note in folder: \(error)")
        }
    }

    func unfileNote(_ noteID: String) {
        guard let db,
              let note = notes.first(where: { $0.id == noteID }),
              let previousFolderID = note.folderID
        else { return }

        do {
            try db.write { db in
                try db.execute(
                    sql: "UPDATE notes SET folderID = NULL, folderOrder = NULL WHERE id = ?",
                    arguments: [noteID]
                )
                try Self.renumberFolderContents(previousFolderID, in: db)
            }
            loadNoteList()
            if currentNote?.id == noteID {
                currentNote?.folderID = nil
                currentNote?.folderOrder = nil
            }
        } catch {
            print("[NoteStore] Failed to unfile note: \(error)")
        }
    }

    func reorderNotes(inFolder folderID: String, orderedIDs: [String]) {
        let currentIDs = notesInFolder(folderID).map(\.id)
        guard orderedIDs.count == currentIDs.count,
              Set(orderedIDs) == Set(currentIDs),
              let db
        else { return }

        do {
            try db.write { db in
                for (index, id) in orderedIDs.enumerated() {
                    try db.execute(
                        sql: "UPDATE notes SET folderOrder = ? WHERE id = ? AND folderID = ?",
                        arguments: [Int64(index), id, folderID]
                    )
                }
            }
            loadNoteList()
            if let currentID = currentNote?.id,
               let index = orderedIDs.firstIndex(of: currentID) {
                currentNote?.folderOrder = Int64(index)
            }
        } catch {
            print("[NoteStore] Failed to reorder notes in folder: \(error)")
        }
    }

    private static func renumberFolderContents(_ folderID: String, in db: Database) throws {
        let remaining = try String.fetchAll(
            db,
            sql: """
                SELECT id FROM notes
                WHERE folderID = ?
                ORDER BY folderOrder ASC, createdAt ASC, id ASC
            """,
            arguments: [folderID]
        )
        for (index, id) in remaining.enumerated() {
            try db.execute(
                sql: "UPDATE notes SET folderOrder = ? WHERE id = ?",
                arguments: [Int64(index), id]
            )
        }
    }

    func deleteNote(_ note: Note) {
        guard notes.count > 1 else { return }
        guard let db else { return }
        let deletedID = note.id
        let deletedIndex = notes.firstIndex { $0.id == deletedID }
        let wasDeletingCurrent = currentNote?.id == deletedID
        let deletedFolderID = note.folderID
        _ = try? db.write { db in
            try Note.deleteOne(db, key: note.id)
            // Keep the folder's manual order contiguous; a gap would otherwise
            // survive until the next drag inside that folder.
            if let deletedFolderID {
                try Self.renumberFolderContents(deletedFolderID, in: db)
            }
        }
        loadNoteList()
        if wasDeletingCurrent, !notes.isEmpty {
            let fallbackIndex = deletedIndex.map { min($0, notes.count - 1) } ?? 0
            switchNote(to: notes[fallbackIndex])
        }
    }

    /// Deletes a note that was never meant to be kept — today, the Bug Report
    /// scratch note.
    ///
    /// Differs from `deleteNote` in two ways that matter for an ephemeral note.
    /// It drops pending debounced writes instead of flushing them, because a
    /// discarded note's edits should not be persisted at all. And it has no
    /// "keep at least one note" guard: that guard silently turns a cancelled bug
    /// report into a permanent note titled "Bug Report" whenever it is the only
    /// note in the store. A replacement is created instead so the app still has
    /// somewhere to type.
    func discardNote(_ note: Note) {
        guard let db else { return }
        cancelPendingSaves()

        let discardedID = note.id
        let discardedIndex = notes.firstIndex { $0.id == discardedID }
        let discardedFolderID = note.folderID
        _ = try? db.write { db in
            try Note.deleteOne(db, key: discardedID)
            if let discardedFolderID {
                try Self.renumberFolderContents(discardedFolderID, in: db)
            }
        }
        loadNoteList()

        guard currentNote?.id == discardedID else { return }
        if notes.isEmpty {
            createNote()
        } else {
            let fallbackIndex = discardedIndex.map { min($0, notes.count - 1) } ?? 0
            switchNote(to: notes[fallbackIndex])
        }
    }

    /// Below this size, an RTF document is cheap enough to fully decode on
    /// every keystroke to check whether the note reads as empty. Real content
    /// blows past this almost immediately, so the decode in `saveContent`
    /// only ever runs near the empty boundary — never while typing into a
    /// note that already has substance. 1500 covers an emptied document that
    /// still carries a leftover font table, color table, or to-do paragraph
    /// style — plain RTF overhead that could exceed a tighter gate and leave
    /// a cleared note stuck with its AI title.
    private static let nearEmptyRTFSizeThreshold = 1500

    func saveContent(_ rtfData: Data) {
        saveContentWork?.cancel()
        // Capture the target note *now*; the write must land on the note being
        // edited, not on whatever currentNote happens to be when the timer fires.
        let targetID = currentNote?.id
        let work = DispatchWorkItem { [weak self] in
            self?.persistContent(rtfData, noteID: targetID)
        }
        saveContentWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        currentNote?.contentRTF = rtfData
        currentNote?.updatedAt = Note.currentTimestamp()
        if let noteID = currentNote?.id,
           let idx = notes.firstIndex(where: { $0.id == noteID }) {
            notes[idx].contentRTF = rtfData
            notes[idx].updatedAt = currentNote?.updatedAt ?? notes[idx].updatedAt
        }

        guard autoTitleEnabled, let targetID, let current = currentNote, !current.autoTitleLocked else { return }
        if current.autoTitleStage > 0,
           rtfData.count < Self.nearEmptyRTFSizeThreshold,
           NotePlainText.of(current).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            revertAutoTitle(noteID: targetID)
        } else {
            autoTitler.noteContentDidChange(noteID: targetID)
        }
    }

    func saveTitle(_ title: String) {
        saveTitleWork?.cancel()
        // Capture the target note *now*; the write must land on the note being
        // edited, not on whatever currentNote happens to be when the timer fires.
        let targetID = currentNote?.id
        let work = DispatchWorkItem { [weak self] in
            self?.persistTitle(title, noteID: targetID)
        }
        saveTitleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        currentNote?.title = title
        currentNote?.updatedAt = Note.currentTimestamp()
        // The user is now naming this note themselves — an in-flight or future
        // auto-title must never overwrite what they typed, ever again.
        currentNote?.autoTitleLocked = true
        if let idx = notes.firstIndex(where: { $0.id == currentNote?.id }) {
            notes[idx].title = title
            notes[idx].autoTitleLocked = true
        }
        if let targetID {
            autoTitler.cancel(noteID: targetID)
        }
    }

    /// Applies an AI-generated title. Called by `NoteAutoTitler` after a
    /// successful generation.
    ///
    /// `expectedStage` is the stage the note was at when the request started;
    /// guarding on it, not just `!autoTitleLocked`, drops a result that
    /// arrives after the note has moved on. `nextStage` is what it advances
    /// to — a single request can clear more than one threshold at once (a big
    /// paste), so it is not always `expectedStage + 1`.
    func applyAutoTitle(_ title: String, noteID: String, expectedStage: Int, nextStage: Int) {
        titleThinking = nil
        guard let db else { return }
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              !notes[idx].autoTitleLocked,
              notes[idx].autoTitleStage == expectedStage
        else { return }

        let now = Note.currentTimestamp()
        _ = try? db.write { db in
            try db.execute(
                sql: "UPDATE notes SET title = ?, updatedAt = ?, autoTitleStage = ? WHERE id = ?",
                arguments: [title, now, nextStage, noteID]
            )
        }
        notes[idx].title = title
        notes[idx].updatedAt = now
        notes[idx].autoTitleStage = nextStage
        if currentNote?.id == noteID {
            currentNote?.title = title
            currentNote?.updatedAt = now
            currentNote?.autoTitleStage = nextStage
            titleReveal = TitleReveal(noteID: noteID, title: title)
        }
    }

    /// Marks a stage as spent without changing the title — used when
    /// generation fails, returns nothing usable, or is unsupported. Same
    /// stale-result guard as `applyAutoTitle`. Returns `false` when that guard
    /// dropped the result, so the caller doesn't report a failure for a note
    /// the user has since titled by hand or that has already moved on.
    @discardableResult
    func spendAutoTitleStage(noteID: String, expectedStage: Int, nextStage: Int) -> Bool {
        titleThinking = nil
        guard let db else { return false }
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              !notes[idx].autoTitleLocked,
              notes[idx].autoTitleStage == expectedStage
        else { return false }

        _ = try? db.write { db in
            try db.execute(
                sql: "UPDATE notes SET autoTitleStage = ? WHERE id = ?",
                arguments: [nextStage, noteID]
            )
        }
        notes[idx].autoTitleStage = nextStage
        if currentNote?.id == noteID {
            currentNote?.autoTitleStage = nextStage
        }
        return true
    }

    /// Restores a note's original "Note N" title and re-arms auto-titling
    /// from stage 0, called when the note's text is cleared back to empty
    /// after an AI title was already applied. Never touches a hand-typed
    /// title — `autoTitleLocked` notes never reach this method's caller.
    private func revertAutoTitle(noteID: String) {
        autoTitler.cancel(noteID: noteID)
        guard let db else { return }
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              !notes[idx].autoTitleLocked,
              notes[idx].autoTitleStage > 0,
              let defaultTitle = notes[idx].autoTitleDefaultTitle
        else { return }

        let now = Note.currentTimestamp()
        _ = try? db.write { db in
            try db.execute(
                sql: "UPDATE notes SET title = ?, updatedAt = ?, autoTitleStage = 0 WHERE id = ?",
                arguments: [defaultTitle, now, noteID]
            )
        }
        notes[idx].title = defaultTitle
        notes[idx].updatedAt = now
        notes[idx].autoTitleStage = 0
        if currentNote?.id == noteID {
            currentNote?.title = defaultTitle
            currentNote?.updatedAt = now
            currentNote?.autoTitleStage = 0
            if titleReveal?.noteID == noteID { titleReveal = nil }
        }
    }

    // MARK: - Private persistence

    private func persistContent(_ rtfData: Data, noteID: String?) {
        guard let db, let noteID else { return }
        let now = Note.currentTimestamp()
        _ = try? db.write { db in
            try db.execute(
                sql: "UPDATE notes SET contentRTF = ?, updatedAt = ? WHERE id = ?",
                arguments: [rtfData, now, noteID]
            )
        }
    }

    private func persistTitle(_ title: String, noteID: String?) {
        guard let db, let noteID else { return }
        let now = Note.currentTimestamp()
        _ = try? db.write { db in
            try db.execute(
                sql: "UPDATE notes SET title = ?, updatedAt = ?, autoTitleLocked = 1 WHERE id = ?",
                arguments: [title, now, noteID]
            )
        }
    }

    // MARK: - Navigation (wrap-around)

    func previousNote() {
        guard let current = currentNote,
              let idx = notes.firstIndex(where: { $0.id == current.id }),
              !notes.isEmpty else { return }
        let prev = idx > 0 ? notes[idx - 1] : notes[notes.count - 1]
        lastNavigationDirection = .backward
        switchNote(to: prev)
    }

    func nextNote() {
        guard let current = currentNote,
              let idx = notes.firstIndex(where: { $0.id == current.id }),
              !notes.isEmpty else { return }
        let next = idx < notes.count - 1 ? notes[idx + 1] : notes[0]
        lastNavigationDirection = .forward
        switchNote(to: next)
    }

    func flushPendingSaves() {
        saveContentWork?.perform()
        saveContentWork?.cancel()
        saveTitleWork?.perform()
        saveTitleWork?.cancel()
    }

    /// Drops in-flight edits without writing them. Used when the note they
    /// target is about to stop existing.
    func cancelPendingSaves() {
        saveContentWork?.cancel()
        saveContentWork = nil
        saveTitleWork?.cancel()
        saveTitleWork = nil
    }
}
