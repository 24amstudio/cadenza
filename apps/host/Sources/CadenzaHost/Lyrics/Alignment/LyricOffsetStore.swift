import Foundation

/// The karaoke nudge a person set for one track, in whole milliseconds. It is kept across launches and updates.
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
}
