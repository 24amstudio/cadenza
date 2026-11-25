import Foundation

struct VideoAlignmentRecord: Equatable, Sendable {
    var studioSongId: String
    var segments: [VideoLyricAligner.Segment]
}

/// The karaoke nudge and computed alignment segments kept per track across launches and updates.
@MainActor
struct LyricOffsetStore {
    let database: Database

    static func trackKey(_ identity: SongIdentity) -> String {
        identity.source + ":" + identity.id
    }

    func offset(for identity: SongIdentity) throws -> Int? {
        try database.query(
            "SELECT user_offset_ms FROM video_lyric_alignments WHERE track_key=?",
            [.text(Self.trackKey(identity))]
        ).first?["user_offset_ms"]?.integer.map(Int.init)
    }

    func save(_ milliseconds: Int, for identity: SongIdentity, at date: Date) throws {
        _ = try database.run(
            """
            INSERT INTO video_lyric_alignments(track_key,user_offset_ms,updated_at_ms) VALUES(?,?,?)
            ON CONFLICT(track_key) DO UPDATE SET user_offset_ms=excluded.user_offset_ms, updated_at_ms=excluded.updated_at_ms
            """,
            [
                .text(Self.trackKey(identity)), .integer(Int64(milliseconds)),
                .integer(Int64(date.timeIntervalSince1970 * 1_000)),
            ])
    }

    func alignment(for identity: SongIdentity) throws -> VideoAlignmentRecord? {
        guard
            let row = try database.query(
                "SELECT studio_song_id,segments_json FROM video_lyric_alignments WHERE track_key=?",
                [.text(Self.trackKey(identity))]
            ).first,
            let studioSongId = row["studio_song_id"]?.string,
            let json = row["segments_json"]?.string,
            let segments = try? JSONDecoder().decode([VideoLyricAligner.Segment].self, from: Data(json.utf8))
        else { return nil }
        return VideoAlignmentRecord(studioSongId: studioSongId, segments: segments)
    }

    func saveAlignment(_ record: VideoAlignmentRecord, for identity: SongIdentity, at date: Date) throws {
        let encoded = String(decoding: try JSONEncoder().encode(record.segments), as: UTF8.self)
        _ = try database.run(
            """
            INSERT INTO video_lyric_alignments(track_key,user_offset_ms,updated_at_ms,studio_song_id,segments_json)
            VALUES(?,0,?,?,?)
            ON CONFLICT(track_key) DO UPDATE SET
                studio_song_id=excluded.studio_song_id,
                segments_json=excluded.segments_json,
                updated_at_ms=excluded.updated_at_ms
            """,
            [
                .text(Self.trackKey(identity)),
                .integer(Int64(date.timeIntervalSince1970 * 1_000)),
                .text(record.studioSongId),
                .text(encoded),
            ])
    }
}
