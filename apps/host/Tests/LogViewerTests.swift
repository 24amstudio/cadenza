import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct LogViewerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func store() throws -> Database {
        try Database(
            url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("logs.sqlite"), role: .logs)
    }

    @discardableResult
    private func insert(
        _ database: Database, ageSeconds: Double, source: String = "host", remoteVersion: String? = nil,
        level: HostLogLevel = .info, category: String = "network", action: String = "peer.connected",
        message: String = "Remote connection opened", metadata: String? = nil
    ) throws -> Int64 {
        try database.run(
            "INSERT INTO system_logs(created_at_ms,unix_timestamp,host_version,remote_version,source,action,level,category,message,metadata_json) VALUES(?,?,?,?,?,?,?,?,?,?)",
            [
                .integer(Int64((now.timeIntervalSince1970 - ageSeconds) * 1_000)),
                .integer(Int64(now.timeIntervalSince1970 - ageSeconds)), .text("0.3.0"),
                remoteVersion.map(SQLValue.text) ?? .null, .text(source), .text(action), .text(level.rawValue),
                .text(category), .text(message), metadata.map(SQLValue.text) ?? .null,
            ])
        return database.lastInsertedRowId
    }

    private func seeded() throws -> Database {
        let database = try store()
        try insert(database, ageSeconds: 90_000, message: "Old start", metadata: #"{"path":"/a"}"#)
        try insert(database, ageSeconds: 7_200, level: .debug, category: "music", action: "music.poll")
        try insert(database, ageSeconds: 1_800, level: .warning, category: "music", message: "Music did not respond")
        try insert(
            database, ageSeconds: 600, source: "remote", remoteVersion: "0.3.0", category: "remote",
            action: "queue.add", message: "Added a song")
        try insert(
            database, ageSeconds: 200, source: "remote", remoteVersion: "cadenza-web 1", level: .error,
            category: "remote", action: "socket.closed", message: "100% broken_pipe")
        try insert(database, ageSeconds: 30, level: .info, category: "network", message: "Pairing started")
        return database
    }

    private func ids(_ database: Database, _ filter: LogFilter) throws -> [String] {
        try LogQueries.recent(database, filter: filter, limit: 100, now: now).map(\.message)
    }

    @Test func sourcesSeparateHostAndEachRemoteApp() throws {
        let database = try seeded()
        #expect(try ids(database, LogFilter(source: .host)).count == 4)
        #expect(try ids(database, LogFilter(source: .android)) == ["Added a song"])
        #expect(try ids(database, LogFilter(source: .web)) == ["100% broken_pipe"])
        #expect(try ids(database, LogFilter(source: .other("watchdog"))).isEmpty)
    }

    @Test func levelIsAMinimumAndCombinesWithCategory() throws {
        let database = try seeded()
        #expect(try ids(database, LogFilter(minimumLevel: .warning)) == ["Music did not respond", "100% broken_pipe"])
        #expect(try ids(database, LogFilter(minimumLevel: .error, category: "music")).isEmpty)
        #expect(try ids(database, LogFilter(category: "music")).count == 2)
    }

    @Test func searchMatchesActionMessageAndMetadataWithoutWildcards() throws {
        let database = try seeded()
        #expect(try ids(database, LogFilter(search: "QUEUE.ADD")) == ["Added a song"])
        #expect(try ids(database, LogFilter(search: "\"path\"")) == ["Old start"])
        #expect(try ids(database, LogFilter(search: "100%")) == ["100% broken_pipe"])
        #expect(try ids(database, LogFilter(search: "_")) == ["100% broken_pipe"])
        #expect(try ids(database, LogFilter(search: "%")) == ["100% broken_pipe"])
    }

    @Test func timeRangesBoundTheReadAndCustomRangesHaveAnEnd() throws {
        let database = try seeded()
        #expect(try ids(database, LogFilter(time: .last5Minutes)) == ["100% broken_pipe", "Pairing started"])
        #expect(try ids(database, LogFilter(time: .lastHour)).count == 4)
        #expect(try ids(database, LogFilter(time: .last24Hours)).count == 5)
        let since = now.addingTimeInterval(-3_000)
        let until = now.addingTimeInterval(-100)
        #expect(
            try ids(database, LogFilter(time: .custom(since: since, until: until)))
                == ["Music did not respond", "Added a song", "100% broken_pipe"])
        #expect(try ids(database, LogFilter(time: .custom(since: since, until: nil))).count == 4)
    }

    @Test func historyIsBoundedToTheNewestRowsInOrder() throws {
        let database = try store()
        for index in 0..<30 { try insert(database, ageSeconds: Double(100 - index), message: "m\(index)") }
        let rows = try LogQueries.recent(database, filter: LogFilter(), limit: 10, now: now)
        #expect(rows.map(\.message) == (20..<30).map { "m\($0)" })
        #expect(rows.map(\.id) == rows.map(\.id).sorted())
    }

    @Test func liveRowsAreFilteredLikeStoredRows() throws {
        let database = try seeded()
        let all = try LogQueries.recent(database, filter: LogFilter(), limit: 100, now: now)
        let filters = [
            LogFilter(source: .host), LogFilter(source: .android), LogFilter(source: .web),
            LogFilter(minimumLevel: .warning), LogFilter(category: "remote"), LogFilter(search: "pairing"),
            LogFilter(search: "BROKEN_PIPE"), LogFilter(time: .lastHour),
            LogFilter(
                source: .host, minimumLevel: .info, category: "music",
                time: .custom(since: now.addingTimeInterval(-5_000), until: nil)),
        ]
        for filter in filters {
            let stored = try LogQueries.recent(database, filter: filter, limit: 100, now: now).map(\.id)
            #expect(all.filter { filter.matches($0, now: now) }.map(\.id) == stored)
        }
    }

    @Test func newestRowsAreRememberedAfterTheViewIsCleared() {
        var buffer = LogBuffer(capacity: 3)
        func row(_ id: Int64) -> LogRow {
            LogRow(
                id: id, createdAtMs: id, hostVersion: "1", remoteVersion: nil, source: "host", action: "a",
                level: .info, category: "c", message: "m\(id)", metadataJSON: nil)
        }
        buffer.append((1...5).map(row))
        #expect(buffer.rows.map(\.id) == [3, 4, 5])
        buffer.clear()
        buffer.append([row(5), row(6)])
        #expect(buffer.rows.map(\.id) == [6])
    }

    @Test func pausingHoldsRowsAndCountsThemUntilResume() {
        var buffer = LogBuffer(capacity: 3)
        func row(_ id: Int64) -> LogRow {
            LogRow(
                id: id, createdAtMs: id, hostVersion: "1", remoteVersion: nil, source: "host", action: "a",
                level: .info, category: "c", message: "m", metadataJSON: nil)
        }
        buffer.append([row(1)])
        buffer.pause()
        buffer.append((2...6).map(row))
        #expect(buffer.rows.map(\.id) == [1])
        #expect(buffer.heldCount == 5)
        buffer.resume()
        #expect(buffer.rows.map(\.id) == [4, 5, 6])
        #expect(buffer.heldCount == 0)
        #expect(!buffer.isPaused)
    }

    @Test func modelListensOnlyWhileStartedAndAppliesTheFilterToLiveRows() async throws {
        let database = try store()
        let logger = try HostLogger(database: database)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let model = LogsModel(defaults: defaults)
        logger.log(.info, category: "boot", action: "service.start", "Before the view opened")
        logger.flush()

        #expect(logger.onFlush == nil)
        model.start(logger: logger)
        await model.settle()
        #expect(model.rows.map(\.message) == ["Before the view opened"])
        #expect(logger.onFlush != nil)

        model.filter.minimumLevel = .warning
        await model.settle()
        #expect(model.rows.isEmpty)
        logger.log(.info, category: "network", action: "peer.connected", "Quiet")
        logger.log(.error, category: "network", action: "socket.failed", "Loud", source: "remote", remoteVersion: "1")
        logger.flush()
        #expect(model.rows.map(\.message) == ["Loud"])
        #expect(model.totalStored == 3)
        #expect(model.categories.contains("network"))

        model.stop()
        #expect(logger.onFlush == nil)
        #expect(model.rows.isEmpty)
        logger.log(.error, category: "network", action: "socket.failed", "Unseen")
        logger.flush()
        #expect(model.rows.isEmpty)
    }

    @Test func clearingTheViewKeepsStoredLogs() async throws {
        let database = try store()
        let logger = try HostLogger(database: database)
        let model = LogsModel(defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        logger.log(.info, category: "boot", action: "a", "One")
        logger.flush()
        model.start(logger: logger)
        await model.settle()
        model.clearView()
        #expect(model.rows.isEmpty)
        #expect(try LogQueries.total(database) == 1)
        logger.log(.info, category: "boot", action: "a", "Two")
        logger.flush()
        #expect(model.rows.map(\.message) == ["Two"])
        model.stop()
    }

    @Test func savedFiltersReturnButTheTimeRangeStartsLive() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let model = LogsModel(defaults: defaults)
        model.filter = LogFilter(
            source: .web, minimumLevel: .warning, category: "remote", search: "pipe", time: .lastHour)
        let restored = LogsModel(defaults: defaults).filter
        #expect(
            restored == LogFilter(source: .web, minimumLevel: .warning, category: "remote", search: "pipe", time: .live)
        )
    }

    @Test func credentialsAreRedactedFromEverythingShownCopiedOrExported() throws {
        let secret = "k3Yq9ZpLm2Xv8Rt5Wd7Bn4Cs6Fh1Jg0AaEeIiOoUu"
        let row = LogRow(
            id: 1, createdAtMs: 1_800_000_000_000, hostVersion: "0.3.0", remoteVersion: nil, source: "host",
            action: "pair", level: .info, category: "pairing",
            message: "Sent Authorization: Bearer abcdef1234567890 and token=\(secret)",
            metadataJSON:
                #"{"pairing_secret":"hunter2hunter2","remote_id":"2f9c1e0a-3b4d-4c5e-8f60-71a2b3c4d5e6","note":"\#(secret)"}"#
        )
        let exported = LogTranscript.text([row]) + (String(data: try LogTranscript.json([row]), encoding: .utf8) ?? "")
        for leaked in [secret, "abcdef1234567890", "hunter2hunter2"] { #expect(!exported.contains(leaked)) }
        #expect(exported.contains("2f9c1e0a-3b4d-4c5e-8f60-71a2b3c4d5e6"))
        #expect(LogRedaction.redact("Queue changed to revision 42") == "Queue changed to revision 42")
    }
}
