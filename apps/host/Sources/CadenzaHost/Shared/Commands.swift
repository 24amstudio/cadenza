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
    // Cast transmission: the device to send Music's audio to, and whether to start or stop sending it.
    var device: String? = nil
    var start: Bool? = nil
    // Where a music video's karaoke line is shown: "host_display" or "cast_transmitter".
    var videoOutput: String? = nil
    // Cast presentation ("auto", "audio_only", or "full_suite") and the AVR lip-sync offset in milliseconds.
    var presentation: String? = nil
    var lipSyncOffsetMs: Int64? = nil
    // The karaoke nudge for one track, in milliseconds, saved on the Host.
    var userOffsetMs: Int64? = nil

    enum CodingKeys: String, CodingKey {
        case kind, song, entryId, beforeEntryId, occurrenceId, positionMs, percent, vocalPercent, enabled, mode
        case name, songs, output, device, start, videoOutput, presentation, lipSyncOffsetMs, userOffsetMs
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(songs, forKey: .songs)
        try container.encodeIfPresent(output, forKey: .output)
        try container.encodeIfPresent(device, forKey: .device)
        try container.encodeIfPresent(start, forKey: .start)
        try container.encodeIfPresent(videoOutput, forKey: .videoOutput)
        try container.encodeIfPresent(presentation, forKey: .presentation)
        try container.encodeIfPresent(lipSyncOffsetMs, forKey: .lipSyncOffsetMs)
        try container.encodeIfPresent(userOffsetMs, forKey: .userOffsetMs)
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
