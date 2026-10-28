import Foundation

struct QueueEntry: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var requestedBy: String?
    var requesterName: String
    var song: Song
    var estimatedWaitMs: Int64?
}

struct CurrentPlayback: Codable, Equatable, Sendable {
    var occurrenceId: String
    var entryId: String?
    var requestedBy: String?
    var requesterName: String
    var song: Song
    var positionMs: Int64
    var sampledAtHostMs: Int64
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
}
