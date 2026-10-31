import Foundation
import os

enum HostLogLevel: String, Sendable {
    case debug, info, warning, error
}

// Logging appends to a lock-protected buffer from any thread, so a call costs an append. The main actor, which
// owns the SQLite connection, writes each batch in one transaction. A burst of control actions therefore becomes
// one commit rather than one commit per entry.
final class HostLogger: @unchecked Sendable {
    struct Entry: Sendable {
        let createdAtMs: Int64
        let unixTimestamp: Int64
        let remoteVersion: String?
        let source: String
        let action: String
        let level: HostLogLevel
        let category: String
        let message: String
        let metadataJSON: String?
    }

    private struct Buffer {
        var entries: [Entry] = []
        var counts: [String: Int] = [:]
        var flushScheduled = false
        var summaryScheduled = false
    }

    private enum FlushPlan {
        case now
        case soon
    }

    private static let batchLimit = 200
    private static let flushDelay = Duration.milliseconds(250)
    private static let summaryInterval = Duration.seconds(60)

    private let buffer = OSAllocatedUnfairLock(initialState: Buffer())
    // Only the main actor touches the database; the buffer is the only state shared across threads.
    private let database: Database
    private var lastPurgeAt = Int64.min

    @MainActor
    init(database: Database) throws {
        self.database = database
        try purge()
    }

    nonisolated func log(
        _ level: HostLogLevel, category: String, action: String, _ message: String,
        source: String = "host", remoteVersion: String? = nil, metadata: [String: String] = [:]
    ) {
        let entry = Entry(
            createdAtMs: wallMs(), unixTimestamp: Int64(Date().timeIntervalSince1970), remoteVersion: remoteVersion,
            source: source, action: String(action.prefix(120)), level: level,
            category: String(category.prefix(80)), message: String(message.prefix(2_000)),
            metadataJSON: metadata.isEmpty ? nil : Self.json(metadata))
        let plan = buffer.withLock { state -> FlushPlan? in
            state.entries.append(entry)
            if state.entries.count >= Self.batchLimit {
                state.flushScheduled = true
                return .now
            }
            guard !state.flushScheduled else { return nil }
            state.flushScheduled = true
            return .soon
        }
        switch plan {
        case .now:
            Task { @MainActor [self] in flush() }
        case .soon:
            Task { @MainActor [self] in
                try? await Task.sleep(for: Self.flushDelay)
                flush()
            }
        case nil:
            break
        }
    }

    /// Counts a high-frequency event, such as a heartbeat, without writing a row for each occurrence.
    /// The totals are written as one summary row per minute.
    nonisolated func count(_ name: String) {
        let schedule = buffer.withLock { state -> Bool in
            // Names can come from the wire, so the number of distinct counters is bounded.
            guard state.counts[name] != nil || state.counts.count < 64 else { return false }
            state.counts[name, default: 0] += 1
            guard !state.summaryScheduled else { return false }
            state.summaryScheduled = true
            return true
        }
        guard schedule else { return }
        Task { @MainActor [self] in
            try? await Task.sleep(for: Self.summaryInterval)
            emitCounts()
        }
    }

    @MainActor
    func flush() {
        let batch = buffer.withLock { state -> [Entry] in
            state.flushScheduled = false
            let entries = state.entries
            state.entries.removeAll(keepingCapacity: true)
            return entries
        }
        if !batch.isEmpty {
            // Logging must never take down playback or control, so a failed write drops the batch.
            try? database.transaction {
                for entry in batch {
                    try database.run(
                        "INSERT INTO system_logs(created_at_ms,unix_timestamp,host_version,remote_version,source,action,level,category,message,metadata_json) VALUES(?,?,?,?,?,?,?,?,?,?)",
                        [
                            .integer(entry.createdAtMs), .integer(entry.unixTimestamp), .text(HostBuild.version),
                            entry.remoteVersion.map(SQLValue.text) ?? .null, .text(entry.source),
                            .text(entry.action), .text(entry.level.rawValue), .text(entry.category),
                            .text(entry.message), entry.metadataJSON.map(SQLValue.text) ?? .null,
                        ])
                }
            }
        }
        if monotonicMs() - lastPurgeAt > 3_600_000 { try? purge() }
    }

    @MainActor
    private func emitCounts() {
        let counts = buffer.withLock { state -> [String: Int] in
            state.summaryScheduled = false
            let counts = state.counts
            state.counts.removeAll(keepingCapacity: true)
            return counts
        }
        guard !counts.isEmpty else { return }
        log(
            .debug, category: "protocol", action: "frames.summary", "Frames received in the last minute",
            metadata: counts.mapValues(String.init))
        flush()
    }

    @MainActor
    func purge() throws {
        let cutoff = wallMs() - Int64(HostLogRetention.days) * 86_400_000
        try database.run("DELETE FROM system_logs WHERE created_at_ms < ?", [.integer(cutoff)])
        lastPurgeAt = monotonicMs()
    }

    private static func json(_ metadata: [String: String]) -> String? {
        (try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])).flatMap {
            String(data: $0, encoding: .utf8)
        }
    }
}
