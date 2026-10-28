import Foundation

struct LRCLIBRecord: Codable, Sendable {
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var duration: Double?
    var instrumental: Bool?
    var plainLyrics: String?
    var syncedLyrics: String?

    enum CodingKeys: String, CodingKey {
        case trackName, artistName, albumName, duration, instrumental, plainLyrics, syncedLyrics
    }

    func matches(_ song: Song) -> Bool {
        guard let trackName, let artistName,
            LyricMatch.normalized(trackName) == LyricMatch.normalized(song.title),
            LyricMatch.artistMatches(artistName, expected: song.artist)
        else { return false }
        if let duration, let expected = song.durationMs {
            return abs(duration * 1_000 - Double(expected)) <= 8_000
        }
        return true
    }
}
