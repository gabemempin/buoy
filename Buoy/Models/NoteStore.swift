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

    private var db: DatabaseQueue?
    private var saveContentWork: DispatchWorkItem?
    private var saveTitleWork: DispatchWorkItem?

    init() {
        setupDatabase()
        loadNoteList()
        if let first = notes.first {
            switchNote(to: first)
        } else {
            createNote()
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

    func createNote() {
        guard let db else { return }
        let count = notes.count
        let now = Note.currentTimestamp()
        let newNote = Note(
            id: Note.newID(),
            title: "Note \(count + 1)",
            contentRTF: Data(),
            createdAt: now,
            updatedAt: now,
            isPinned: false,
            pinnedOrder: nil
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

    func saveContent(_ rtfData: Data) {
        saveContentWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistContent(rtfData)
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
    }

    func saveTitle(_ title: String) {
        saveTitleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistTitle(title)
        }
        saveTitleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        currentNote?.title = title
        currentNote?.updatedAt = Note.currentTimestamp()
        if let idx = notes.firstIndex(where: { $0.id == currentNote?.id }) {
            notes[idx].title = title
        }
    }

    // MARK: - Private persistence

    private func persistContent(_ rtfData: Data) {
        guard let db, let note = currentNote else { return }
        let now = Note.currentTimestamp()
        _ = try? db.write { db in
            try db.execute(
                sql: "UPDATE notes SET contentRTF = ?, updatedAt = ? WHERE id = ?",
                arguments: [rtfData, now, note.id]
            )
        }
    }

    private func persistTitle(_ title: String) {
        guard let db, let note = currentNote else { return }
        let now = Note.currentTimestamp()
        _ = try? db.write { db in
            try db.execute(
                sql: "UPDATE notes SET title = ?, updatedAt = ? WHERE id = ?",
                arguments: [title, now, note.id]
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
}
