import Foundation

/// Bounded reads of the stored logs. Every query has a limit or is an aggregate, so opening the view never loads
/// the whole table.
@MainActor
enum LogQueries {
    static let columns =
        "id,created_at_ms,host_version,remote_version,source,action,level,category,message,metadata_json"

    /// The newest `limit` entries that match, oldest first.
    static func recent(_ database: Database, filter: LogFilter, limit: Int, now: Date = Date()) throws -> [LogRow] {
        let (clause, bindings) = filter.sql(now: now)
        let rows = try database.query(
            "SELECT \(columns) FROM system_logs" + (clause.isEmpty ? "" : " WHERE " + clause)
                + " ORDER BY id DESC LIMIT ?",
            bindings + [.integer(Int64(limit))])
        return rows.compactMap(LogRow.init).reversed()
    }

    static func sources(_ database: Database) throws -> [String] {
        try database.query("SELECT DISTINCT source FROM system_logs ORDER BY source").compactMap {
            $0["source"]?.string
        }
    }

    static func categories(_ database: Database) throws -> [String] {
        try database.query("SELECT DISTINCT category FROM system_logs ORDER BY category").compactMap {
            $0["category"]?.string
        }
    }

    static func newestId(_ database: Database) throws -> Int64 {
        try database.query("SELECT COALESCE(MAX(id),0) AS id FROM system_logs").first?["id"]?.integer ?? 0
    }

    static func total(_ database: Database) throws -> Int {
        Int(try database.query("SELECT COUNT(*) AS n FROM system_logs").first?["n"]?.integer ?? 0)
    }
}
