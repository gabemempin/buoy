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

    // MARK: - Convenience

    static func newID() -> String {
        return String(Int64(Date().timeIntervalSince1970 * 1000))
    }

    static func currentTimestamp() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
}
