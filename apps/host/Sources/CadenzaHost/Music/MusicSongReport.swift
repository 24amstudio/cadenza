import Foundation

/// The song `music.js` reports for the current track. The script's output is untrusted at this boundary. A radio
/// stream has no finite length and may have no artist, so each fallback applies only to the field that is missing.
struct MusicSongReport: Decodable, Sendable {
    let song: Song
    let isLiveRadio: Bool

    private enum CodingKeys: String, CodingKey {
        case isLiveRadio
    }

    init(from decoder: Decoder) throws {
        var value = try Song(from: decoder)
        let flagged = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Bool.self, forKey: .isLiveRadio)
        // A missing or non-positive length is live even when the script's flag says otherwise, so a stream always has no timing.
        let live = (flagged ?? false) || (value.durationMs ?? 0) <= 0
        if let duration = value.durationMs, duration <= 0 { value.durationMs = nil }
        if live, value.artist.isEmpty { value.artist = "Live Radio" }
        song = value
        isLiveRadio = live
    }
}
