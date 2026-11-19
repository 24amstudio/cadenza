import Foundation

/// Plain-text and JSON forms of log rows, for Copy and Export. Rows are already redacted.
enum LogTranscript {
    static func line(_ row: LogRow) -> String {
        var parts = [
            row.timestamp, row.level.title.uppercased().padding(toLength: 7, withPad: " ", startingAt: 0),
            row.sourceTitle, row.category, row.action, row.message,
        ]
        if let metadata = row.metadataJSON { parts.append(metadata) }
        return parts.joined(separator: "  ")
    }

    static func text(_ rows: [LogRow]) -> String { rows.map(line).joined(separator: "\n") + "\n" }

    static func json(_ rows: [LogRow]) throws -> Data {
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)
        let objects: [[String: Any]] = rows.map { row in
            var object: [String: Any] = [
                "id": row.id,
                "time": Date(timeIntervalSince1970: Double(row.createdAtMs) / 1_000).formatted(iso),
                "level": row.level.rawValue, "source": row.sourceTitle, "category": row.category,
                "action": row.action, "message": row.message, "host_version": row.hostVersion,
            ]
            if let remote = row.remoteVersion { object["remote_version"] = remote }
            if let metadata = row.metadataJSON {
                object["metadata"] =
                    metadata.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? metadata
            }
            return object
        }
        return try JSONSerialization.data(
            withJSONObject: objects, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}
