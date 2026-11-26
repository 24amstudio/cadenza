import CryptoKit
import Foundation

/// The track metadata, timed lines, and media URLs that a stage receiver shows for one song occurrence.
struct StageTrackSuite: Equatable, Sendable {
    struct Word: Equatable, Sendable {
        let text: String
        let startMs: Int64
        let endMs: Int64

        var json: [String: Any] { ["text": text, "start_ms": startMs, "end_ms": endMs] }
    }

    struct Line: Equatable, Sendable {
        let id: String
        let text: String
        let startMs: Int64
        let endMs: Int64
        let words: [Word]
        let translation: String?
        let romanized: String?
        let align: String?

        var json: [String: Any] {
            var object: [String: Any] = [
                "id": id, "text": text, "start_ms": startMs, "end_ms": endMs, "words": words.map(\.json),
            ]
            if let translation { object["translation"] = translation }
            if let romanized { object["romanized"] = romanized }
            if let align { object["align"] = align }
            return object
        }
    }

    static let maximumLines = 2_000
    static let maximumTextLength = 20_000

    let trackId: String
    let title: String
    let artist: String
    let album: String
    let durationMs: Int64
    let quality: String?
    let artworkUrl: String?
    let motionUrl: String?
    let lines: [Line]

    /// Builds the suite for one occurrence. `suiteId` is an opaque identifier, so receivers never see a catalog ID.
    static func make(
        suiteId: String, song: Song, quality: String, document: LyricDocument?, mediaBase: String
    ) -> StageTrackSuite {
        let lines = (document?.lines ?? []).prefix(maximumLines).enumerated().map { index, line in
            Line(
                id: String((line.id.isEmpty ? "line-\(index)" : line.id).prefix(256)),
                text: String(line.text.prefix(maximumTextLength)),
                startMs: max(0, line.startMs), endMs: max(line.startMs, line.endMs),
                words: line.words.prefix(1_000).map {
                    Word(text: String($0.text.prefix(1_000)), startMs: max(0, $0.startMs), endMs: max(0, $0.endMs))
                },
                translation: line.translation.map { String($0.prefix(maximumTextLength)) },
                romanized: line.romanized.map { String($0.prefix(maximumTextLength)) },
                align: line.align == "end" ? "end" : "start")
        }
        return StageTrackSuite(
            trackId: suiteId, title: String(song.title.prefix(300)), artist: String(song.artist.prefix(300)),
            album: String(song.album.prefix(300)), durationMs: max(0, song.durationMs ?? 0),
            quality: badge(for: quality), artworkUrl: "\(mediaBase)/api/v1/cast/artwork/\(suiteId).jpg",
            motionUrl: "\(mediaBase)/api/v1/cast/motion/\(suiteId).mp4", lines: lines)
    }

    /// The Music audio tier as the badge that receivers show. Nil while the tier is unknown, so no badge is invented.
    static func badge(for quality: String) -> String? {
        switch quality {
        case "lossless": "Lossless"
        case "hi_res_lossless": "Hi-Res Lossless"
        case "dolby_atmos": "Dolby Atmos"
        case "aac": "AAC"
        default: nil
        }
    }

    /// A stable opaque ID for one song, so a receiver can prefetch and request media without a catalog identity. Repeats
    /// of the same song share it, and their lyrics and media are the same.
    static func suiteId(for identity: SongIdentity) -> String {
        SHA256.hash(data: Data("\(identity.source):\(identity.id)".utf8)).prefix(12).map { String(format: "%02x", $0) }
            .joined()
    }
}
