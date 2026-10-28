import Foundation

struct Frame: Codable, Sendable {
    var version: Int = 1
    var type: String
    var requestId: String? = nil
    var commandId: String? = nil
    var hostEpoch: String? = nil
    var expiresAtHostMs: Int64? = nil
    var expectedRevision: Int64? = nil
    var action: CommandAction? = nil
    var name: String? = nil
    var heartbeat: Bool? = nil
    var auth: DeviceAuth? = nil
    var pair: PairRequest? = nil
    var welcome: Welcome? = nil
    var snapshot: HostSnapshot? = nil
    var query: String? = nil
    var scope: String? = nil
    var songs: [Song]? = nil
    var lyrics: LyricDocument? = nil
    var clock: ClockSample? = nil
    var errorCode: String? = nil
    var message: String? = nil
    var outcome: String? = nil
    var resolved: Bool? = nil
    var revision: Int64? = nil
    var eventId: String? = nil
    var sequence: Int64? = nil
    var occurrenceId: String? = nil
    var song: SongIdentity? = nil
    var songMetadata: Song? = nil
    var playCountDelta: Int? = nil
    var playedMsDelta: Int64? = nil
    var logAction: String? = nil
    var logLevel: String? = nil
    var logMessage: String? = nil
    var artworkUrl: String? = nil
    var artworkDataBase64: String? = nil
}
