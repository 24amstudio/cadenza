import Foundation

enum CadenzaError: LocalizedError, Sendable {
    case failure(String, String)

    var code: String {
        switch self {
        case .failure(let code, _): return code
        }
    }

    var errorDescription: String? {
        switch self {
        case .failure(_, let message): return message
        }
    }
}

func identifier() -> String { UUID().uuidString.lowercased() }

func monotonicMs() -> Int64 {
    Int64(ProcessInfo.processInfo.systemUptime * 1_000)
}

func wallMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

struct SongIdentity: Codable, Hashable, Sendable {
    var source: String
    var id: String
}

struct Song: Codable, Identifiable, Equatable, Sendable {
    var source: String
    var id: String
    var title: String
    var artist: String
    var album: String = ""
    var durationMs: Int64? = nil
    var artworkUrl: String? = nil
    var url: String? = nil

    var identity: SongIdentity { SongIdentity(source: source, id: id) }
}

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

struct CommandFailure: Sendable {
    let outcome: String
    let code: String

    init(dispatched: Bool, code: String) {
        if dispatched {
            outcome = "unconfirmed"
            self.code = "outcome_unknown"
        } else if code == "expired" {
            outcome = "expired"
            self.code = code
        } else {
            outcome = "rejected"
            self.code = code == "outcome_unknown" ? "music_unavailable" : code
        }
    }
}

struct CommandAction: Codable, Sendable {
    var kind: String
    var song: SongIdentity? = nil
    var entryId: String? = nil
    var beforeEntryId: String? = nil
    var occurrenceId: String? = nil
    var positionMs: Int64? = nil
    var percent: Int? = nil

    enum CodingKeys: String, CodingKey {
        case kind, song, entryId, beforeEntryId, occurrenceId, positionMs, percent
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(song, forKey: .song)
        try container.encodeIfPresent(entryId, forKey: .entryId)
        if kind == "queue.move" { try container.encode(beforeEntryId, forKey: .beforeEntryId) }
        if kind == "queue.play_now" {
            try container.encode(occurrenceId, forKey: .occurrenceId)
        } else {
            try container.encodeIfPresent(occurrenceId, forKey: .occurrenceId)
        }
        try container.encodeIfPresent(positionMs, forKey: .positionMs)
        try container.encodeIfPresent(percent, forKey: .percent)
    }
}

struct DeviceAuth: Codable, Sendable {
    var remoteId: String
    var token: String
    var lastCreditSequence: Int64
    var name: String? = nil
    var heartbeat: Bool? = nil
}

struct PairRequest: Codable, Sendable {
    var secret: String
    var name: String
    var heartbeat: Bool? = nil
}

struct PairingInvitation: Codable, Sendable {
    var version: Int = 1
    var host: String
    var port: Int
    var fingerprint: String
    var certificateDerBase64: String
    var secret: String
    var hostName: String
}

struct UpdateConfiguration: Codable, Sendable {
    var repository: String = ""
    var publicKeySpkiBase64: String = ""
}

struct Welcome: Codable, Sendable {
    var hostId: String
    var hostName: String
    var hostEpoch: String
    var remoteId: String
    var token: String? = nil
    var hostTimeMs: Int64
    var protocolMajor: Int = 1
    var protocolMinor: Int = 1
    var updates: UpdateConfiguration
    var capabilities: [String] = [
        "playback", "library", "catalog.public-web", "queue.native-accessibility",
        "lyrics.music-cache", "lyrics.english-translation", "analytics", "updates.signed", "queue.play-next",
        "remote.configure", "state.heartbeat",
    ]
}

struct LyricWord: Codable, Sendable {
    var text: String
    var startMs: Int64
    var endMs: Int64
}

struct LyricLine: Codable, Identifiable, Sendable {
    var id: String
    var text: String
    var startMs: Int64
    var endMs: Int64
    var words: [LyricWord] = []
    var translation: String? = nil
}

struct LyricDocument: Codable, Sendable {
    var occurrenceId: String
    var revision: String
    var language: String?
    var translationSource: String
    var lines: [LyricLine]
    var issue: String? = nil
}

struct ClockSample: Codable, Sendable {
    var sentAtRemoteMs: Int64
    var receivedAtHostMs: Int64? = nil
    var sentAtHostMs: Int64? = nil
}

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
}

enum Wire {
    static let maximumMessageBytes = 1_048_576
    static let maximumCounter: Int64 = 9_007_199_254_740_991

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    static func isIdentifier(_ value: String) -> Bool {
        UUID(uuidString: value) != nil && value == value.lowercased()
    }

    static func validate(_ identity: SongIdentity) -> Bool {
        let pattern = identity.source == "catalog" ? "^[0-9]{1,20}$" : "^[0-9A-F]{16}$"
        return ["catalog", "library"].contains(identity.source)
            && identity.id.range(of: pattern, options: .regularExpression) != nil
    }
}
