import Foundation

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
    var vocalPercent: Int? = nil
    var enabled: Bool? = nil
    var mode: String? = nil
    // Library write-back: the playlist name and the library songs to add to it.
    var name: String? = nil
    var songs: [SongIdentity]? = nil
    // The UID of the audio output to make the Mac's default.
    var output: String? = nil

    enum CodingKeys: String, CodingKey {
        case kind, song, entryId, beforeEntryId, occurrenceId, positionMs, percent, vocalPercent, enabled, mode
        case name, songs, output
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(songs, forKey: .songs)
        try container.encodeIfPresent(output, forKey: .output)
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
        try container.encodeIfPresent(vocalPercent, forKey: .vocalPercent)
        try container.encodeIfPresent(enabled, forKey: .enabled)
        try container.encodeIfPresent(mode, forKey: .mode)
    }
}
