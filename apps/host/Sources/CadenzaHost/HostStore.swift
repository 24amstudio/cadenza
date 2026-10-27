import CryptoKit
import Foundation

@MainActor
final class HostStore {
    let database: Database
    let hostId: String
    private(set) var epoch = identifier()
    private let authorization: String

    init(directory: URL, defaults: UserDefaults = .standard) throws {
        database = try Database(url: directory.appendingPathComponent("cadence.sqlite"))
        if let existing = defaults.string(forKey: "hostId") {
            hostId = existing
        } else {
            hostId = identifier()
            defaults.set(hostId, forKey: "hostId")
        }
        guard let policy = HostResources.bundle.url(forResource: "authorize-command", withExtension: "sql", subdirectory: "storage") else {
            throw CadenzaError.failure("storage", "The command policy is missing.")
        }
        authorization = try String(contentsOf: policy, encoding: .utf8)
        let prior = try database.query("SELECT occurrence_id FROM playback_sessions LIMIT 1").isEmpty ? 0 : 1
        try database.run("UPDATE host_state SET runtime_epoch=?, observation_gap=max(observation_gap,?)", [.text(epoch), .integer(Int64(prior))])
        let prepared = try database.query("SELECT plan_json FROM command_intents WHERE phase='prepared'")
        for row in prepared {
            if let text = row["plan_json"]?.string,
               let plan = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String],
               let id = plan["entry_id"] { try remove(id) }
        }
        try database.run("UPDATE command_intents SET phase='complete' WHERE phase='prepared'")
    }

    func beginEpoch() throws {
        epoch = identifier()
        try database.run("UPDATE host_state SET runtime_epoch=?", [.text(epoch)])
    }

    func recordObservationGap() throws {
        try database.run("UPDATE host_state SET observation_gap=1 WHERE observation_gap=0")
    }

    var revision: Int64 {
        get throws { try database.query("SELECT queue_revision FROM host_state").first?["queue_revision"]?.integer ?? 0 }
    }

    var crossEdits: Bool {
        get throws { try database.query("SELECT allow_cross_remote_edits FROM host_state").first?["allow_cross_remote_edits"]?.integer == 1 }
    }

    func bump() throws {
        guard try revision < Wire.maximumCounter else {
            throw CadenzaError.failure("storage", "The queue revision needs maintenance before more changes.")
        }
        try database.run("UPDATE host_state SET queue_revision=queue_revision+1")
    }

    func setPolicy(_ enabled: Bool) throws {
        try database.transaction {
            try database.run("UPDATE host_state SET allow_cross_remote_edits=?", [.integer(enabled ? 1 : 0)])
            try bump()
        }
    }

    func pair(name: String) throws -> (String, String) {
        let id = identifier()
        let reference = "remote.\(id)"
        let token = try SecureStore.randomToken()
        try SecureStore.write(reference, Data(token.utf8))
        do {
            try database.run("""
                INSERT INTO paired_remotes(remote_id,display_name,credential_reference,paired_at_ms)
                VALUES(?,?,?,?)
                """, [.text(id), .text(name), .text(reference), .integer(wallMs())])
        } catch { try? SecureStore.delete(reference); throw error }
        return (id, token)
    }

    func authenticate(_ auth: DeviceAuth) throws -> Bool {
        guard Wire.isIdentifier(auth.remoteId), auth.token.utf8.count <= 128,
              let row = try database.query(
                "SELECT credential_reference FROM paired_remotes WHERE remote_id=? AND revoked_at_ms IS NULL",
                [.text(auth.remoteId)]
              ).first,
              let reference = row["credential_reference"]?.string,
              let data = try SecureStore.read(reference),
              let token = String(data: data, encoding: .utf8) else { return false }
        return SecureStore.equal(token, auth.token)
    }

    func remotes() throws -> [SQLRow] {
        try database.query("SELECT remote_id, display_name, revoked_at_ms FROM paired_remotes ORDER BY paired_at_ms")
    }

    func remoteName(_ id: String?) throws -> String {
        guard let id else { return "Mac" }
        return try database.query("SELECT display_name FROM paired_remotes WHERE remote_id=?", [.text(id)])
            .first?["display_name"]?.string ?? "Unpaired Remote"
    }

    func revoke(_ id: String) throws {
        let reference = try database.query(
            "SELECT credential_reference FROM paired_remotes WHERE remote_id=?", [.text(id)]
        ).first?["credential_reference"]?.string
        try database.run("UPDATE paired_remotes SET revoked_at_ms=? WHERE remote_id=?", [.integer(wallMs()), .text(id)])
        if let reference { try SecureStore.delete(reference) }
    }

    func authorize(actor: String, command: Frame, entryId: String?) throws {
        guard let action = command.action, let expiry = command.expiresAtHostMs,
              let expected = command.expectedRevision, let epoch = command.hostEpoch else {
            throw CadenzaError.failure("invalid_command", "Invalid command envelope.")
        }
        let decision = try database.query(authorization, named: [
            "actor_id": .text(actor), "host_epoch": .text(epoch), "now_host_ms": .integer(monotonicMs()),
            "expires_at_host_ms": .integer(expiry), "expected_revision": .integer(expected),
            "kind": .text(action.kind), "entry_id": entryId.map(SQLValue.text) ?? .null,
            "before_entry_id": action.beforeEntryId.map(SQLValue.text) ?? .null,
        ]).first?["decision"]?.string ?? "invalid_command"
        guard decision == "allowed" else {
            throw CadenzaError.failure(decision, explanation(decision))
        }
    }

    private func explanation(_ code: String) -> String {
        switch code {
        case "forbidden": "Host settings protect this request. You can change only your own requests."
        case "revoked": "This Remote was unpaired. Pair it again from Cadenza Host."
        case "stale_revision", "stale_occurrence": "Playback or the queue changed. Review the current state and retry."
        case "expired", "invalid_deadline": "The request expired before it could be applied."
        default: "The action cannot be applied to the current Music state."
        }
    }

    func pending() throws -> [SQLRow] {
        try database.query("SELECT * FROM queue_entries WHERE state='pending' ORDER BY sort_key")
    }

    func entry(_ id: String) throws -> SQLRow? {
        try database.query("SELECT * FROM queue_entries WHERE entry_id=?", [.text(id)]).first
    }

    func song(_ row: SQLRow) -> Song {
        Song(
            source: row["source"]?.string ?? "unknown", id: row["song_id"]?.string ?? "",
            title: row["title"]?.string ?? "", artist: row["artist"]?.string ?? "",
            album: row["album"]?.string ?? "", durationMs: row["duration_ms"]?.integer,
            artworkUrl: row["artwork_url"]?.string, url: row["song_url"]?.string
        )
    }

    func insert(_ song: Song, owner: String, id: String, confirmed: Bool = true) throws {
        guard Wire.validate(song.identity), !song.title.isEmpty, song.title.count <= 500,
              song.artist.count <= 500, song.album.count <= 500 else {
            throw CadenzaError.failure("invalid_command", "This song's metadata exceeds the supported limits.")
        }
        let count = try database.query("SELECT count(*) AS total FROM queue_entries WHERE state IN ('pending','current')").first?["total"]?.integer ?? 0
        guard count < 256 else { throw CadenzaError.failure("queue_full", "The queue limit is 256 requests. Remove a request and retry.") }
        let order = try database.query("SELECT coalesce(max(sort_key),0)+1024 AS next FROM queue_entries WHERE state IN ('pending','current')").first?["next"]?.integer ?? 1024
        try database.run("""
            INSERT INTO queue_entries(
              entry_id,requested_by,source,song_id,title,artist,duration_ms,sort_key,created_at_ms,album,artwork_url,song_url,native_confirmed
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, [
                .text(id), .text(owner), .text(song.source), .text(song.id), .text(song.title), .text(song.artist),
                song.durationMs.map(SQLValue.integer) ?? .null, .integer(order), .integer(wallMs()), .text(song.album),
                song.artworkUrl.map(SQLValue.text) ?? .null, song.url.map(SQLValue.text) ?? .null,
                .integer(confirmed ? 1 : 0),
            ])
    }

    func remove(_ id: String) throws {
        try database.run("UPDATE queue_entries SET state='canceled' WHERE entry_id=? AND state='pending'", [.text(id)])
    }

    func reorder(_ ids: [String]) throws {
        try database.transaction {
            let pendingIds = try pending().compactMap { $0["entry_id"]?.string }
            guard Set(ids).count == ids.count, Set(ids).isSubset(of: Set(pendingIds)) else {
                throw CadenzaError.failure("invalid_state", "The saved queue order contains missing or repeated requests.")
            }
            let complete = ids + pendingIds.filter { !ids.contains($0) }
            let limits = try database.query("SELECT coalesce(min(sort_key),0) AS low,coalesce(max(sort_key),0) AS high FROM queue_entries WHERE state='pending'").first
            let low = limits?["low"]?.integer ?? 0
            let high = limits?["high"]?.integer ?? 0
            guard low >= -Wire.maximumCounter, high <= Wire.maximumCounter else {
                throw CadenzaError.failure("storage", "Saved queue order exceeds its supported range.")
            }
            let shift = max(high, 0) - min(low, 0) + 1
            try database.run("UPDATE queue_entries SET sort_key=sort_key-? WHERE state='pending'", [.integer(shift)])
            for (index, id) in complete.enumerated() {
                try database.run("UPDATE queue_entries SET sort_key=? WHERE entry_id=? AND state='pending'", [
                    .integer(Int64(index + 1) * 1024), .text(id),
                ])
            }
        }
    }

    func beginOccurrence(entryId: String?, song: Song) throws -> String {
        let occurrence = identifier()
        try database.transaction {
            try database.run("UPDATE queue_entries SET state='completed' WHERE state='current'")
            if let entryId {
                try database.run("UPDATE queue_entries SET state='current', sort_key=0 WHERE entry_id=?", [.text(entryId)])
            }
            try database.run("UPDATE host_state SET current_occurrence_id=?", [.text(occurrence)])
            let owner = try entryId.flatMap { try entry($0)?["requested_by"]?.string }
            if Wire.validate(song.identity) {
                try database.run("""
                    INSERT INTO playback_sessions(occurrence_id,entry_id,requested_by,source,song_id)
                    VALUES(?,?,?,?,?)
                    """, [
                        .text(occurrence), entryId.map(SQLValue.text) ?? .null, owner.map(SQLValue.text) ?? .null,
                        .text(song.source), .text(song.id),
                    ])
            }
            try bump()
        }
        return occurrence
    }

    func observe(occurrence: String, milliseconds: Int64) throws {
        guard milliseconds > 0, milliseconds <= 60_000 else { return }
        try database.transaction {
            guard let session = try database.query(
                "SELECT * FROM playback_sessions WHERE occurrence_id=?", [.text(occurrence)]
            ).first, let owner = session["requested_by"]?.string,
                let source = session["source"]?.string, let song = session["song_id"]?.string else { return }
            guard let remote = try database.query(
                "SELECT next_credit_sequence FROM paired_remotes WHERE remote_id=?", [.text(owner)]
            ).first, let sequence = remote["next_credit_sequence"]?.integer, sequence < Wire.maximumCounter else {
                throw CadenzaError.failure("storage", "Playback credits need storage maintenance.")
            }
            let count: Int64 = session["counted"]?.integer == 1 ? 0 : 1
            try database.run("""
                INSERT INTO playback_credit_outbox(
                  remote_id,sequence,event_id,occurrence_id,source,song_id,play_count_delta,played_ms_delta
                ) VALUES(?,?,?,?,?,?,?,?)
                """, [
                    .text(owner), .integer(sequence), .text(identifier()), .text(occurrence), .text(source),
                    .text(song), .integer(count), .integer(milliseconds),
                ])
            try database.run("UPDATE playback_sessions SET counted=1 WHERE occurrence_id=?", [.text(occurrence)])
            try database.run("UPDATE paired_remotes SET next_credit_sequence=next_credit_sequence+1 WHERE remote_id=?", [.text(owner)])
        }
    }

    func credits(_ remoteId: String, after sequence: Int64) throws -> [Frame] {
        try database.query("""
            SELECT o.*,q.title,q.artist,q.album,q.duration_ms,q.artwork_url,q.song_url
            FROM playback_credit_outbox o
            LEFT JOIN playback_sessions s ON s.occurrence_id=o.occurrence_id
            LEFT JOIN queue_entries q ON q.entry_id=s.entry_id
            WHERE o.remote_id=? AND o.sequence>? AND o.acknowledged=0 ORDER BY o.sequence LIMIT 8
            """, [.text(remoteId), .integer(sequence)]).map { row in
                Frame(
                    type: "analytics.credit", eventId: row["event_id"]?.string,
                    sequence: row["sequence"]?.integer, occurrenceId: row["occurrence_id"]?.string,
                    song: SongIdentity(source: row["source"]?.string ?? "", id: row["song_id"]?.string ?? ""),
                    songMetadata: row["title"]?.string == nil ? nil : self.song(row),
                    playCountDelta: row["play_count_delta"]?.integer.map(Int.init),
                    playedMsDelta: row["played_ms_delta"]?.integer
                )
            }
    }

    func acknowledge(_ remote: String, through sequence: Int64) throws {
        let next = try database.query(
            "SELECT next_credit_sequence FROM paired_remotes WHERE remote_id=?", [.text(remote)]
        ).first?["next_credit_sequence"]?.integer ?? 1
        guard sequence >= 0 && sequence < next else { throw CadenzaError.failure("invalid_command", "Invalid analytics acknowledgment.") }
        try database.run(
            "UPDATE playback_credit_outbox SET acknowledged=1 WHERE remote_id=? AND sequence<=?",
            [.text(remote), .integer(sequence)]
        )
    }
}
