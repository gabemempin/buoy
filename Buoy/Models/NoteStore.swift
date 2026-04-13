import Foundation
import GRDB
import Observation

@Observable
final class NoteStore {
    var notes: [Note] = []
    var currentNote: Note?

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

    func createNote() {
        guard let db else { return }
        let count = notes.count
        let now = Note.currentTimestamp()
        let newNote = Note(
            id: Note.newID(),
            title: "Note \(count + 1)",
            contentRTF: Data(),
            createdAt: now,
            updatedAt: now
        )
        _ = try? db.write { db in
            try newNote.insert(db)
        }
        loadNoteList()
        currentNote = newNote
    }

    func deleteNote(_ note: Note) {
        guard notes.count > 1 else { return }
        guard let db else { return }
        _ = try? db.write { db in
            try Note.deleteOne(db, key: note.id)
        }
        let deletedID = note.id
        loadNoteList()
        if currentNote?.id == deletedID {
            if let first = notes.first {
                switchNote(to: first)
            }
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
        switchNote(to: prev)
    }

    func nextNote() {
        guard let current = currentNote,
              let idx = notes.firstIndex(where: { $0.id == current.id }),
              !notes.isEmpty else { return }
        let next = idx < notes.count - 1 ? notes[idx + 1] : notes[0]
        switchNote(to: next)
    }

    func flushPendingSaves() {
        saveContentWork?.perform()
        saveContentWork?.cancel()
        saveTitleWork?.perform()
        saveTitleWork?.cancel()
    }
}
