import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct HostLoggerTests {
    @Test func entriesAreWrittenInOneBatchOnlyWhenFlushed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        let database = try Database(url: directory.appendingPathComponent("logs.sqlite"), role: .logs)
        let logger = try HostLogger(database: database)

        logger.log(
            .info, category: "command", action: "command.received", "Remote requested a pause", source: "remote",
            remoteVersion: "1", metadata: ["kind": "playback.pause"])
        logger.log(.warning, category: "music", action: "music.seek", "Music did not respond")
        #expect(try loggedCount(database) == 0)

        logger.flush()
        #expect(try loggedCount(database) == 2)
        let first = try #require(
            database.query("SELECT source,metadata_json FROM system_logs ORDER BY id LIMIT 1").first)
        #expect(first["source"]?.string == "remote")
        #expect(first["metadata_json"]?.string == #"{"kind":"playback.pause"}"#)
    }

    private func loggedCount(_ database: Database) throws -> Int64 {
        try database.query("SELECT COUNT(*) AS n FROM system_logs").first?["n"]?.integer ?? 0
    }
}
