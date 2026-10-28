import Foundation

enum HostLogLevel: String, Sendable {
    case debug, info, warning, error
}

@MainActor
final class HostLogger {
    private let database: Database
    private var lastPurgeAt = Int64.min

    init(database: Database) throws {
        self.database = database
        try purge()
    }

    func log(
        _ level: HostLogLevel, category: String, action: String, _ message: String,
        source: String = "host", remoteVersion: String? = nil, metadata: [String: String] = [:]
    ) {
        let safeCategory = String(category.prefix(80))
        let safeMessage = String(message.prefix(2_000))
        var metadataJSON: String?
        if !metadata.isEmpty {
            metadataJSON = try? String(
                data: JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]), encoding: .utf8)
        }
        do {
            try database.run(
                "INSERT INTO system_logs(created_at_ms,unix_timestamp,host_version,remote_version,source,action,level,category,message,metadata_json) VALUES(?,?,?,?,?,?,?,?,?,?)",
                [
                    .integer(wallMs()), .integer(Int64(Date().timeIntervalSince1970)), .text(HostBuild.version),
                    remoteVersion.map(SQLValue.text) ?? .null, .text(source), .text(String(action.prefix(120))),
                    .text(level.rawValue),
                    .text(safeCategory), .text(safeMessage), metadataJSON.map(SQLValue.text) ?? .null,
                ])
            if monotonicMs() - lastPurgeAt > 3_600_000 { try purge() }
        } catch {
            // Logging must never take down playback or control.
        }
    }

    func purge() throws {
        let days = min(max(UserDefaults.standard.integer(forKey: "systemLogRetentionDays"), 7), 30)
        let cutoff = wallMs() - Int64(days) * 86_400_000
        try database.run("DELETE FROM system_logs WHERE created_at_ms < ?", [.integer(cutoff)])
        lastPurgeAt = monotonicMs()
    }
}
