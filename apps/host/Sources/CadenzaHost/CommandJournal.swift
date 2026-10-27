import CryptoKit
import Foundation

@MainActor
final class CommandJournal {
    let store: HostStore
    init(store: HostStore) { self.store = store }

    func fingerprint(_ frame: Frame) throws -> String {
        SHA256.hash(data: try Wire.encode(frame)).map { String(format: "%02x", $0) }.joined()
    }

    func previous(_ command: Frame, actor: String) throws -> Frame? {
        guard let commandId = command.commandId else { return nil }
        let digest = try fingerprint(command)
        let rows = try store.database.query(
            """
            SELECT payload_sha256,response_json FROM command_receipts WHERE remote_id=? AND command_id=?
            """, [.text(actor), .text(commandId)])
        if let row = rows.first {
            guard row["payload_sha256"]?.string == digest else {
                throw CadenzaError.failure(
                    "command_conflict", "This command ID was already used for a different action.")
            }
            if let text = row["response_json"]?.string {
                var response = try Wire.decode(Frame.self, from: Data(text.utf8))
                response.hostEpoch = store.epoch
                return response
            }
        }
        if let intent = try store.database.query(
            """
            SELECT payload_sha256,phase FROM command_intents WHERE remote_id=? AND command_id=?
            """, [.text(actor), .text(commandId)]
        ).first {
            guard intent["payload_sha256"]?.string == digest else {
                throw CadenzaError.failure("command_conflict", "This command ID was already used for another action.")
            }
            if intent["phase"]?.string == "complete" {
                return try result(
                    command, outcome: "expired", code: "expired",
                    message: "The request was not dispatched before Host restarted.")
            }
            return try result(command, outcome: "unconfirmed", code: "outcome_unknown")
        }
        return nil
    }

    func status(_ request: Frame, actor: String, queued: Bool) throws -> Frame {
        guard let id = request.commandId, Wire.isIdentifier(id) else {
            throw CadenzaError.failure("invalid_command", "Invalid command status request.")
        }
        if let row = try store.database.query(
            "SELECT response_json FROM command_receipts WHERE remote_id=? AND command_id=?", [.text(actor), .text(id)]
        ).first, let text = row["response_json"]?.string {
            var response = try Wire.decode(Frame.self, from: Data(text.utf8))
            response.hostEpoch = store.epoch
            return response
        }
        let intent = try store.database.query(
            "SELECT phase FROM command_intents WHERE remote_id=? AND command_id=?", [.text(actor), .text(id)]
        ).first
        if queued || intent?["phase"]?.string == "dispatched" || intent?["phase"]?.string == "prepared" {
            return try result(request, outcome: "unconfirmed", code: "outcome_unknown")
        }
        return try result(
            request, outcome: "expired", code: "expired", message: "Host has no dispatched action for this command.")
    }

    func prepare(_ command: Frame, actor: String, plan: String?) throws {
        guard let id = command.commandId else { throw CadenzaError.failure("invalid_command", "Missing command ID.") }
        let text = String(decoding: try Wire.encode(command), as: UTF8.self)
        try store.database.run(
            """
            INSERT INTO command_intents(remote_id,command_id,payload_sha256,command_json,plan_json,phase,created_at_ms)
            VALUES(?,?,?,?,?,'prepared',?)
            """,
            [
                .text(actor), .text(id), .text(try fingerprint(command)), .text(text),
                plan.map(SQLValue.text) ?? .null, .integer(wallMs()),
            ])
    }

    func dispatched(_ command: Frame, actor: String) throws {
        try store.database.run(
            "UPDATE command_intents SET phase='dispatched' WHERE remote_id=? AND command_id=?",
            [.text(actor), .text(command.commandId ?? "")]
        )
    }

    func result(_ command: Frame, outcome: String, code: String? = nil, message: String? = nil) throws -> Frame {
        var result = Frame(type: "command.result")
        result.commandId = command.commandId
        result.hostEpoch = store.epoch
        result.outcome = outcome
        result.errorCode = code
        result.message = message
        result.revision = try store.revision
        return result
    }

    func finish(_ command: Frame, actor: String, result: Frame) throws {
        guard let id = command.commandId, let outcome = result.outcome else { return }
        let response = String(decoding: try Wire.encode(result), as: UTF8.self)
        try store.database.transaction {
            try store.database.run(
                """
                INSERT INTO command_receipts(
                  remote_id,command_id,payload_sha256,outcome,revision,created_at_ms,error_code,response_json
                ) VALUES(?,?,?,?,?,?,?,?)
                ON CONFLICT(remote_id,command_id) DO UPDATE SET
                  outcome=excluded.outcome,revision=excluded.revision,error_code=excluded.error_code,response_json=excluded.response_json
                WHERE command_receipts.payload_sha256=excluded.payload_sha256
                """,
                [
                    .text(actor), .text(id), .text(try fingerprint(command)), .text(outcome),
                    .integer(result.revision ?? 0), .integer(wallMs()),
                    result.errorCode.map(SQLValue.text) ?? .null, .text(response),
                ])
            if outcome != "unconfirmed" || result.resolved == true {
                try store.database.run(
                    "UPDATE command_intents SET phase='complete' WHERE remote_id=? AND command_id=?",
                    [.text(actor), .text(id)])
            }
        }
    }

    func reconcileQueue(assignments: Set<String>) throws {
        let intents = try store.database.query(
            """
            SELECT i.* FROM command_intents i JOIN command_receipts r
              ON i.remote_id=r.remote_id AND i.command_id=r.command_id
            WHERE r.outcome='unconfirmed' AND i.plan_json IS NOT NULL
            """)
        for intent in intents {
            guard let actor = intent["remote_id"]?.string, let text = intent["command_json"]?.string,
                let plan = intent["plan_json"]?.string,
                let object = try JSONSerialization.jsonObject(with: Data(plan.utf8)) as? [String: String],
                let entryId = object["entry_id"]
            else { continue }
            let command = try Wire.decode(Frame.self, from: Data(text.utf8))
            let entry = try store.entry(entryId)
            let confirmed =
                command.action?.kind == "queue.enqueue" && assignments.contains(entryId)
                || command.action?.kind == "queue.play_now" && entry?["state"]?.string == "current"
            if confirmed {
                try finish(command, actor: actor, result: result(command, outcome: "applied"))
            } else if entry?["state"]?.string == "canceled" {
                try finish(
                    command, actor: actor,
                    result: result(
                        command, outcome: "rejected", code: "missing_request",
                        message:
                            "Host reviewed the native queue and cancelled this saved request. Its earlier native outcome remains unknown."
                    ))
            }
        }
        let remaining = try store.database.query(
            """
            SELECT i.remote_id,i.command_json FROM command_intents i JOIN command_receipts r
              ON i.remote_id=r.remote_id AND i.command_id=r.command_id
            WHERE r.outcome='unconfirmed' AND i.phase!='complete'
            """)
        for intent in remaining {
            guard let actor = intent["remote_id"]?.string, let text = intent["command_json"]?.string else { continue }
            let command = try Wire.decode(Frame.self, from: Data(text.utf8))
            var reviewed = try result(
                command, outcome: "unconfirmed", code: "outcome_unknown",
                message:
                    "Host reviewed Music's current state. The original outcome remains unknown. Check playback and the queue before making another request."
            )
            reviewed.resolved = true
            try finish(command, actor: actor, result: reviewed)
        }
    }
}
