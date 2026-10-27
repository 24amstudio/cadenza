import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct DatabaseTests {
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
}
