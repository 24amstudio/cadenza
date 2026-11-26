import Foundation

struct QueueEntry: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var requestedBy: String?
    var requesterName: String
    var song: Song
    var estimatedWaitMs: Int64?
    var estimatedStartHostMs: Int64? = nil
    var estimateStatus: String? = nil
}

struct CurrentPlayback: Codable, Equatable, Sendable {
    var occurrenceId: String
    var entryId: String?
    var requestedBy: String?
    var requesterName: String
    var song: Song
    var positionMs: Int64
    var sampledAtHostMs: Int64
    // The song's cover at most 32 by 32 pixels, base64 JPEG. It arrives with the song, so both appear together.
    var artworkPreview: String? = nil
    // A radio stream. Clients show a LIVE badge and do not offer timeline scrubbing.
    var isLiveRadio: Bool = false
}

struct HostSnapshot: Codable, Equatable, Sendable {
    var hostId: String
    var hostEpoch: String
    var revision: Int64
    var sequence: Int64
    var hostTimeMs: Int64
    var allowCrossRemoteEdits: Bool
    var playing: Bool
    var volume: Int
    var current: CurrentPlayback?
    var queue: [QueueEntry]
    var totalRemainingMs: Int64?
    var quality: String = "unknown"
    var incoming: Song? = nil
    var mixing: Bool? = nil
    var synchronized: Bool = false
    var issue: String? = nil
    var observationGap: Bool = false
    var sing: SingSession? = nil
    var autoPlay: [AutoPlayItem] = []
    // Music's shuffle switch and its repeat mode ("off", "one", or "all").
    var shuffle: Bool = false
    var `repeat`: String = "off"
    // The Host's thermal and power budget. Remotes back off optional prefetching and log uploads when it is constrained.
    var hostBudget: String? = nil
    // The Mac's audio outputs, with the default one marked. Remotes offer them as the place Music plays.
    var audioOutputs: [AudioOutput] = []
    // Google Cast devices on the LAN and the presentation mode chosen in Settings. Audio is not sent to them yet.
    var cast: CastSnapshot? = nil
    // Where a music video's karaoke line is shown: "host_display" or "cast_transmitter".
    var videoOutput: String? = nil
    // The AVR lip-sync offset in milliseconds. Karaoke lines are chosen this much later to match the delayed audio.
    var lipSyncOffsetMs: Int? = nil
}

// Music's AutoPlay songs, which play after the queue. Only the first few travel, so a state frame stays small.
struct AutoPlayItem: Codable, Equatable, Sendable {
    static let shownLimit = 8
    var title: String
    var artist: String
}
