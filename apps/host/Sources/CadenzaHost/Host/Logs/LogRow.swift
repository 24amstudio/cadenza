import Foundation

/// One stored log entry, prepared for display. Text that could carry a credential is redacted once, here, so no
/// view, copy or export can show the original.
struct LogRow: Identifiable, Hashable, Sendable {
    static let webRemotePrefix = "cadenza-web"

    private static let timeStyle = Date.VerbatimFormatStyle(
        format:
            "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
        locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent, calendar: .autoupdatingCurrent)
    private static let dayStyle = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)",
        locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent, calendar: .autoupdatingCurrent)

    let id: Int64
    let createdAtMs: Int64
    let hostVersion: String
    let remoteVersion: String?
    let source: String
    let action: String
    let level: HostLogLevel
    let category: String
    let message: String
    let metadataJSON: String?
    /// Local time of day with milliseconds, formatted once.
    let time: String
    let day: String

    init(
        id: Int64, createdAtMs: Int64, hostVersion: String, remoteVersion: String?, source: String, action: String,
        level: HostLogLevel, category: String, message: String, metadataJSON: String?
    ) {
        self.id = id
        self.createdAtMs = createdAtMs
        self.hostVersion = hostVersion
        self.remoteVersion = remoteVersion
        self.source = source
        self.action = action
        self.level = level
        self.category = category
        self.message = LogRedaction.redact(message)
        self.metadataJSON = metadataJSON.map(LogRedaction.redact)
        let date = Date(timeIntervalSince1970: Double(createdAtMs) / 1_000)
        time = date.formatted(Self.timeStyle)
        day = date.formatted(Self.dayStyle)
    }

    init?(_ row: SQLRow) {
        guard let id = row["id"]?.integer, let createdAtMs = row["created_at_ms"]?.integer,
            let level = row["level"]?.string.flatMap(HostLogLevel.init(rawValue:))
        else { return nil }
        self.init(
            id: id, createdAtMs: createdAtMs, hostVersion: row["host_version"]?.string ?? "",
            remoteVersion: row["remote_version"]?.string, source: row["source"]?.string ?? "",
            action: row["action"]?.string ?? "",
            level: level, category: row["category"]?.string ?? "", message: row["message"]?.string ?? "",
            metadataJSON: row["metadata_json"]?.string)
    }

    init(id: Int64, host entry: HostLogger.Entry) {
        self.init(
            id: id, createdAtMs: entry.createdAtMs, hostVersion: HostBuild.version, remoteVersion: entry.remoteVersion,
            source: entry.source, action: entry.action, level: entry.level, category: entry.category,
            message: entry.message, metadataJSON: entry.metadataJSON)
    }

    /// Remote entries do not say which app sent them; the Remote version string does.
    var isWebRemote: Bool { source == "remote" && remoteVersion?.hasPrefix(Self.webRemotePrefix) == true }

    var sourceTitle: String {
        switch source {
        case "host": "Host"
        case "remote": isWebRemote ? "Remote (Web)" : "Remote (Android)"
        default: source
        }
    }

    var timestamp: String { day + " " + time }

    /// The metadata, indented and key-sorted, or the text as stored when it is not JSON.
    var prettyMetadata: String? {
        guard let metadataJSON else { return nil }
        guard let data = metadataJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
            let text = String(data: pretty, encoding: .utf8)
        else { return metadataJSON }
        return text
    }
}
