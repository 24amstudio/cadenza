import Foundation

/// Keeps each paired Remote's latest taste digest. A Remote sends its digest at every hello, so a newer one replaces the old.
@MainActor
struct TasteDigestStore {
    let database: Database

    func save(_ digest: RemoteTasteDigest, remoteId: String, at date: Date) throws {
        let json = String(decoding: try Wire.encode(digest), as: UTF8.self)
        _ = try database.run(
            """
            INSERT INTO remote_taste_digests(remote_id,digest_json,updated_at_ms) VALUES(?,?,?)
            ON CONFLICT(remote_id) DO UPDATE SET digest_json=excluded.digest_json, updated_at_ms=excluded.updated_at_ms
            """,
            [.text(remoteId), .text(json), .integer(Int64(date.timeIntervalSince1970 * 1_000))])
    }

    func load(remoteId: String) throws -> RemoteTasteDigest? {
        guard
            let json = try database.query(
                "SELECT digest_json FROM remote_taste_digests WHERE remote_id=?", [.text(remoteId)]
            ).first?["digest_json"]?.string
        else { return nil }
        return try Wire.decode(RemoteTasteDigest.self, from: Data(json.utf8))
    }

    func remove(remoteId: String) throws {
        _ = try database.run("DELETE FROM remote_taste_digests WHERE remote_id=?", [.text(remoteId)])
    }
}
