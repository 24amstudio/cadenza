import Foundation

enum LogSourceFilter: Hashable, Codable, Sendable {
    case all, host, android, web
    /// A source value other than the ones Cadenza writes today, found in the stored logs.
    case other(String)

    var title: String {
        switch self {
        case .all: "All platforms"
        case .host: "Host only"
        case .android: "Remote (Android)"
        case .web: "Remote (Web)"
        case .other(let source): source
        }
    }
}

enum LogTimeRange: Hashable, Codable, Sendable {
    case live, last5Minutes, lastHour, last24Hours
    case custom(since: Date, until: Date?)

    var title: String {
        switch self {
        case .live: "Live"
        case .last5Minutes: "Last 5 minutes"
        case .lastHour: "Last hour"
        case .last24Hours: "Last 24 hours"
        case .custom: "Since…"
        }
    }

    /// Whether new entries can still fall inside the range. A range with an end is a fixed slice of the past.
    var followsLiveEntries: Bool {
        if case .custom(_, let until) = self { return until == nil }
        return true
    }
}

/// What the Logs view shows. The same filter builds the SQL for stored entries and tests live ones in memory, so
/// both paths agree.
struct LogFilter: Hashable, Codable, Sendable {
    var source: LogSourceFilter = .all
    var minimumLevel: HostLogLevel = .debug
    var category: String?
    var search = ""
    var time: LogTimeRange = .live

    var searchTerm: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isDefault: Bool { self == LogFilter() }

    func lowerBoundMs(now: Date) -> Int64? {
        let seconds: Double
        switch time {
        case .live: return nil
        case .last5Minutes: seconds = 300
        case .lastHour: seconds = 3_600
        case .last24Hours: seconds = 86_400
        case .custom(let since, _): return Int64(since.timeIntervalSince1970 * 1_000)
        }
        return Int64((now.timeIntervalSince1970 - seconds) * 1_000)
    }

    var upperBoundMs: Int64? {
        if case .custom(_, let until?) = time { return Int64(until.timeIntervalSince1970 * 1_000) }
        return nil
    }

    /// The WHERE conditions, joined by AND, and their bindings. Empty when nothing is filtered.
    func sql(now: Date) -> (clause: String, bindings: [SQLValue]) {
        var conditions: [String] = []
        var bindings: [SQLValue] = []
        switch source {
        case .all: break
        case .host: conditions.append("source = 'host'")
        case .android:
            conditions.append(
                "(source = 'remote' AND (remote_version IS NULL OR remote_version NOT LIKE '\(LogRow.webRemotePrefix)%'))"
            )
        case .web: conditions.append("(source = 'remote' AND remote_version LIKE '\(LogRow.webRemotePrefix)%')")
        case .other(let name):
            conditions.append("source = ?")
            bindings.append(.text(name))
        }
        if minimumLevel > .debug {
            let allowed = HostLogLevel.allCases.filter { $0 >= minimumLevel }
            conditions.append("level IN (" + allowed.map { _ in "?" }.joined(separator: ",") + ")")
            bindings += allowed.map { .text($0.rawValue) }
        }
        if let category {
            conditions.append("category = ?")
            bindings.append(.text(category))
        }
        if !searchTerm.isEmpty {
            conditions.append(
                "(action LIKE ? ESCAPE '\\' OR message LIKE ? ESCAPE '\\' OR metadata_json LIKE ? ESCAPE '\\')")
            bindings += Array(repeating: .text(Self.likePattern(searchTerm)), count: 3)
        }
        if let lower = lowerBoundMs(now: now) {
            conditions.append("created_at_ms >= ?")
            bindings.append(.integer(lower))
        }
        if let upper = upperBoundMs {
            conditions.append("created_at_ms <= ?")
            bindings.append(.integer(upper))
        }
        return (conditions.joined(separator: " AND "), bindings)
    }

    func matches(_ row: LogRow, now: Date) -> Bool {
        switch source {
        case .all: break
        case .host: if row.source != "host" { return false }
        case .android: if row.source != "remote" || row.isWebRemote { return false }
        case .web: if !row.isWebRemote { return false }
        case .other(let name): if row.source != name { return false }
        }
        if row.level < minimumLevel { return false }
        if let category, row.category != category { return false }
        if let lower = lowerBoundMs(now: now), row.createdAtMs < lower { return false }
        if let upper = upperBoundMs, row.createdAtMs > upper { return false }
        guard !searchTerm.isEmpty else { return true }
        return [row.action, row.message, row.metadataJSON ?? ""].contains {
            $0.range(of: searchTerm, options: [.caseInsensitive]) != nil
        }
    }

    /// Escapes LIKE wildcards so the search text is matched literally.
    static func likePattern(_ term: String) -> String {
        let escaped = term.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%" + escaped + "%"
    }
}
