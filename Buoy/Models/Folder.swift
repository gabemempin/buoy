import Foundation
import GRDB

/// A one-level grouping of notes shown in the All Notes panel.
///
/// Folders are a *view* over the note list, not a move: a note that belongs to
/// a folder still appears in the All Notes section below. `Note.folderID` holds
/// the membership (at most one folder per note) and `Note.folderOrder` the
/// manual order inside it.
///
/// There is deliberately no foreign key from `notes.folderID` to this table —
/// deleting a folder must leave its notes alone, which is a single
/// `UPDATE notes SET folderID = NULL`.
struct Folder: Identifiable, Codable, FetchableRecord, PersistableRecord, Equatable {
    var id: String
    var name: String
    /// Manual position among the folder rows. Contiguous from 0 after any
    /// reorder or delete.
    var sortOrder: Int64
    /// Disclosure state, persisted so a collapsed folder stays collapsed
    /// across launches. New folders start expanded so the rename field is
    /// visible in context.
    var isExpanded: Bool
    var createdAt: Int64

    static let databaseTableName = "folders"

    enum Columns: String, ColumnExpression {
        case id, name, sortOrder, isExpanded, createdAt
    }

    /// Prefixed so a folder id can never collide with a `Note` id, which is a
    /// bare millisecond timestamp.
    static func newID() -> String {
        "folder-\(Int64(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6))"
    }

    static let defaultName = "New Folder"

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Folder.defaultName : trimmed
    }
}
