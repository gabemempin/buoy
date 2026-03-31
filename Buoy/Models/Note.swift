import Foundation
import GRDB

struct Note: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    var contentRTF: Data
    var createdAt: Int64
    var updatedAt: Int64

    static let databaseTableName = "notes"

    enum Columns: String, ColumnExpression {
        case id, title, contentRTF, createdAt, updatedAt
    }

    static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    static func newID() -> String { String(nowMs()) }
    static func currentTimestamp() -> Int64 { nowMs() }
}
