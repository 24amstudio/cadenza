import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct DatabaseTests {
    @Test func hostCachePersistsAndReportsUsage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadenza-cache-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try Database(url: directory.appendingPathComponent("test.sqlite"))
        let cache = try HostCache(
            database: database, mediaDirectory: directory.appendingPathComponent("media"), limitBytes: 256 * 1_048_576)
        try cache.put(Data("lyrics".utf8), for: "lyrics:catalog:123", kind: "lyrics")
        #expect(try cache.data(for: "lyrics:catalog:123") == Data("lyrics".utf8))
        let stats = try cache.stats()
        #expect(stats.entries == 1)
        #expect(stats.bytes == 6)
        try cache.removeAll()
        let empty = try cache.stats()
        #expect(empty.entries == 0)
    }

    @Test func missingMediaIsRemovedFromCacheIndex() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadenza-media-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try Database(url: directory.appendingPathComponent("test.sqlite"))
        let media = directory.appendingPathComponent("media")
        let cache = try HostCache(database: database, mediaDirectory: media, limitBytes: 256 * 1_048_576)
        try cache.put(Data([1, 2, 3]), for: "artwork:catalog:123", kind: "artwork")
        let file = try #require(
            FileManager.default.contentsOfDirectory(at: media, includingPropertiesForKeys: nil).first)
        try FileManager.default.removeItem(at: file)
        #expect(try cache.data(for: "artwork:catalog:123") == nil)
        #expect(try cache.stats().entries == 0)
    }

    @Test func rollbackAndBackupPreserveCommittedData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadenza-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try Database(url: directory.appendingPathComponent("test.sqlite"))
        #expect(try database.query("PRAGMA user_version").first?["user_version"]?.integer == 2)
        let id = "00000000-0000-4000-8000-000000000001"
        let name = "Example's tablet; DROP TABLE paired_remotes;"
        try database.run(
            "INSERT INTO paired_remotes(remote_id,display_name,credential_reference,paired_at_ms) VALUES(?,?,?,?)",
            [.text(id), .text(name), .text("test-reference"), .integer(0)]
        )
        #expect(throws: (any Error).self) {
            try database.transaction {
                try database.run(
                    "UPDATE paired_remotes SET display_name=? WHERE remote_id=?", [.text("rolled back"), .text(id)])
                throw CadenzaError.failure("test", "Deliberate transaction failure.")
            }
        }
        #expect(
            try database.query("SELECT display_name FROM paired_remotes WHERE remote_id=?", [.text(id)]).first?[
                "display_name"]?.string == name)
        let backup = directory.appendingPathComponent("backup.sqlite")
        try database.backup(to: backup)
        let restored = try Database(url: backup)
        #expect(
            try restored.query("SELECT display_name FROM paired_remotes WHERE remote_id=?", [.text(id)]).first?[
                "display_name"]?.string == name)
    }

    @Test func repeatedPartialReordersRetainUnmatchedRequestsWithoutKeyCollisions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadenza-test-" + UUID().uuidString)
        let suite = "CadenzaTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try HostStore(directory: directory, defaults: defaults)
        let owner = "00000000-0000-4000-8000-000000000001"
        try store.database.run(
            "INSERT INTO paired_remotes(remote_id,display_name,credential_reference,paired_at_ms) VALUES(?,?,?,?)",
            [.text(owner), .text("Synthetic Remote"), .text("unused-test-reference"), .integer(0)]
        )
        let song = Song(source: "catalog", id: "100", title: "Example", artist: "Example artist")
        try store.insert(song, owner: owner, id: "first", confirmed: false)
        try store.insert(song, owner: owner, id: "second")
        try store.reorder(["second"])
        try store.reorder(["second"])
        #expect(try store.pending().compactMap { $0["entry_id"]?.string } == ["second", "first"])
        try store.reorder(["first", "second"])
        #expect(try store.pending().compactMap { $0["entry_id"]?.string } == ["first", "second"])
    }

    @Test func anObservationGapSurvivesRestartAfterSessionCompaction() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadenza-test-" + UUID().uuidString)
        let suite = "CadenzaTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try HostStore(directory: directory, defaults: defaults)
        try store.recordObservationGap()
        #expect(try store.database.query("SELECT occurrence_id FROM playback_sessions").isEmpty)
        let reopened = try HostStore(directory: directory, defaults: defaults)
        #expect(
            try reopened.database.query("SELECT observation_gap FROM host_state").first?["observation_gap"]?.integer
                == 1)
    }

    @Test func hostOriginatedPlaybackCountsOncePerConnectedRemote() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadenza-test-" + UUID().uuidString)
        let suite = "CadenzaTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try HostStore(directory: directory, defaults: defaults)
        for remote in ["remote-a", "remote-b", "remote-c"] {
            try store.database.run(
                "INSERT INTO paired_remotes(remote_id,display_name,credential_reference,paired_at_ms) VALUES(?,?,?,?)",
                [.text(remote), .text(remote), .text("reference-" + remote), .integer(0)])
        }
        try store.database.run(
            "INSERT INTO playback_sessions(occurrence_id,entry_id,requested_by,source,song_id) VALUES('occurrence',NULL,NULL,'catalog','100')"
        )
        try store.observe(occurrence: "occurrence", milliseconds: 1_000, listeners: ["remote-a", "remote-b"])
        try store.observe(occurrence: "occurrence", milliseconds: 2_000, listeners: ["remote-a", "remote-c"])
        let totals = try store.database.query(
            """
            SELECT remote_id,sum(play_count_delta) AS plays,sum(played_ms_delta) AS played
            FROM playback_credit_outbox GROUP BY remote_id ORDER BY remote_id
            """)
        #expect(totals.map { $0["remote_id"]?.string } == ["remote-a", "remote-b", "remote-c"])
        #expect(totals.map { $0["plays"]?.integer } == [1, 1, 1])
        #expect(totals.map { $0["played"]?.integer } == [3_000, 1_000, 2_000])
    }
}
