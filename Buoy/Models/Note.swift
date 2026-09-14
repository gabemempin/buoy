import Foundation
import GRDB

struct Note: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    var contentRTF: Data
    var createdAt: Int64
    var updatedAt: Int64
    var isPinned: Bool
    var pinnedOrder: Int64?
    /// How many auto-title attempts this note has consumed. Indexes into
    /// `NoteAutoTitler.thresholds` — 0 is untitled by AI, and the note is
    /// finished once this reaches `thresholds.count`. Never advances once
    /// `autoTitleLocked`.
    var autoTitleStage: Int
    /// True once the user has typed a title themselves (or the note was
    /// never eligible, e.g. the Bug Report scratch note) — auto-titling
    /// never touches this note again.
    var autoTitleLocked: Bool
    /// The "Note N" title this note was created with, so clearing the note's
    /// text back to empty can restore it after an AI title was applied.
    var autoTitleDefaultTitle: String?

    static let databaseTableName = "notes"

    enum Columns: String, ColumnExpression {
        case id, title, contentRTF, createdAt, updatedAt, isPinned, pinnedOrder
        case autoTitleStage, autoTitleLocked, autoTitleDefaultTitle
    }

    static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    static func newID() -> String { String(nowMs()) }
    static func currentTimestamp() -> Int64 { nowMs() }
}
