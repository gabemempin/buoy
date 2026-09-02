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
            self?.autoTitleEnabled = AppSettings.load().autoTitleEnabled
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

        try? migrator.migrate(db)
    }

    // MARK: - CRUD

    func loadNoteList() {
        guard let db else { return }
        notes = (try? db.read { db in
            try Note
                .order(Note.Columns.createdAt.asc)
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
            autoTitleDefaultTitle: defaultTitle
        )
        _ = try? db.write { db in
            try newNote.insert(db)
        }
        loadNoteList()
        currentNote = newNote
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

    func deleteNote(_ note: Note) {
        guard notes.count > 1 else { return }
        guard let db else { return }
        let deletedID = note.id
        let deletedIndex = notes.firstIndex { $0.id == deletedID }
        let wasDeletingCurrent = currentNote?.id == deletedID
        _ = try? db.write { db in
            try Note.deleteOne(db, key: note.id)
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
        _ = try? db.write { db in
            try Note.deleteOne(db, key: discardedID)
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
    /// note that already has substance.
    private static let nearEmptyRTFSizeThreshold = 600

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
    /// stale-result guard as `applyAutoTitle`.
    func spendAutoTitleStage(noteID: String, expectedStage: Int, nextStage: Int) {
        titleThinking = nil
        guard let db else { return }
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              !notes[idx].autoTitleLocked,
              notes[idx].autoTitleStage == expectedStage
        else { return }

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
