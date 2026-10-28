import CoreFoundation
import Foundation

enum ProtocolValidation {
    private static let commands: [String: Set<String>] = [
        "queue.enqueue": ["kind", "song"],
        "queue.play_next": ["kind", "song"],
        "queue.play_now": ["kind", "song", "occurrence_id"],
        "queue.remove": ["kind", "entry_id"],
        "queue.move": ["kind", "entry_id", "before_entry_id"],
        "playback.pause": ["kind", "occurrence_id"],
        "playback.resume": ["kind", "occurrence_id"],
        "playback.skip": ["kind", "occurrence_id"],
        "playback.previous": ["kind", "occurrence_id"],
        "playback.stop": ["kind", "occurrence_id"],
        "playback.seek": ["kind", "occurrence_id", "position_ms"],
        "playback.volume": ["kind", "percent"],
    ]

    static func decode(_ data: Data) throws -> Frame {
        guard data.count <= Wire.maximumMessageBytes else { throw invalid("The message is too large.") }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else { throw invalid("Expected a protocol message object.") }
        if type != "command" { try validateSession(type, object: object) }
        let frame = try Wire.decode(Frame.self, from: data)
        guard frame.version == 1 else {
            throw CadenzaError.failure(
                "incompatible_protocol", "Update Cadenza Host and Remote to compatible versions.")
        }
        if frame.type == "command" {
            try validateCommand(frame, raw: data)
        } else if ![
            "pair", "hello", "clock", "search", "song.prepare", "operation.cancel", "lyrics.get", "analytics.ack",
            "state.get", "command.status", "remote.configure", "log.report", "artwork.get",
        ].contains(frame.type) {
            throw invalid("Unknown message type.")
        }
        if let requestId = frame.requestId, !Wire.isIdentifier(requestId) {
            throw invalid("Invalid request identifier.")
        }
        if let query = frame.query, query.count > 200 { throw invalid("Search is limited to 200 characters.") }
        return frame
    }

    private static func validateSession(_ type: String, object: [String: Any]) throws {
        let required: [String: Set<String>] = [
            "pair": ["pair"], "hello": ["auth"], "clock": ["clock"],
            "search": ["request_id", "query", "scope"], "song.prepare": ["request_id", "song"],
            "operation.cancel": ["request_id"], "lyrics.get": [], "analytics.ack": ["sequence"],
            "state.get": [], "command.status": ["command_id"],
            "remote.configure": ["name", "heartbeat", "request_id"],
            "log.report": ["log_action", "log_level", "log_message"],
            "artwork.get": ["request_id", "artwork_url"],
        ]
        guard let fields = required[type] else { throw invalid("Unknown message type.") }
        let keys = Set(object.keys)
        guard keys.isSuperset(of: fields.union(["version", "type"])),
            keys.isSubset(of: fields.union(["version", "type", "request_id"]))
        else {
            throw invalid("The message contains unexpected or missing fields.")
        }
        if type == "pair" { try nested(object["pair"], fields: ["name", "secret"], optional: ["heartbeat", "remote_version"]) }
        if type == "log.report" {
            guard let level = object["log_level"] as? String, ["debug", "info", "warning", "error"].contains(level),
                let action = object["log_action"] as? String, (1...120).contains(action.count),
                let message = object["log_message"] as? String, (1...2_000).contains(message.count)
            else { throw invalid("Invalid log report.") }
        }
        if type == "artwork.get" {
            guard let value = object["artwork_url"] as? String, ArtworkProvider.isAllowedURL(value) else {
                throw invalid("Invalid artwork address.")
            }
        }
        if type == "hello" {
            try nested(
                object["auth"], fields: ["remote_id", "token", "last_credit_sequence"], optional: ["name", "heartbeat", "remote_version"])
        }
        if type == "clock" { try nested(object["clock"], fields: ["sent_at_remote_ms"]) }
        if type == "song.prepare" { try nested(object["song"], fields: ["source", "id"]) }
        if type == "search", let scope = object["scope"] as? String, !["catalog", "library"].contains(scope) {
            throw invalid("Choose catalog or library search.")
        }
        if let auth = object["auth"] as? [String: Any] {
            guard let id = auth["remote_id"] as? String, Wire.isIdentifier(id),
                let token = auth["token"] as? String, (32...128).contains(token.count)
            else { throw invalid("Invalid authentication.") }
            try counter(auth["last_credit_sequence"])
        }
        if let pair = object["pair"] as? [String: Any] {
            guard let secret = pair["secret"] as? String, (32...128).contains(secret.count),
                let name = pair["name"] as? String, (1...80).contains(name.count)
            else { throw invalid("Invalid pairing details.") }
        }
        if let clock = object["clock"] as? [String: Any] { try counter(clock["sent_at_remote_ms"]) }
        if type == "analytics.ack" { try counter(object["sequence"]) }
        if type == "command.status" {
            guard let id = object["command_id"] as? String, Wire.isIdentifier(id) else {
                throw invalid("Invalid command identifier.")
            }
        }
    }

    private static func nested(_ value: Any?, fields: Set<String>, optional: Set<String> = []) throws {
        guard let value = value as? [String: Any], Set(value.keys).isSuperset(of: fields),
            Set(value.keys).isSubset(of: fields.union(optional))
        else { throw invalid("Invalid message payload.") }
    }

    private static func counter(_ value: Any?) throws {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
            value.doubleValue.isFinite, value.doubleValue.rounded(.towardZero) == value.doubleValue,
            value.doubleValue >= 0, value.doubleValue <= Double(Wire.maximumCounter)
        else { throw invalid("Invalid protocol counter.") }
    }

    private static func validateCommand(_ frame: Frame, raw: Data) throws {
        guard raw.count <= 65_536,
            let commandId = frame.commandId, Wire.isIdentifier(commandId),
            let epoch = frame.hostEpoch, Wire.isIdentifier(epoch),
            let expiry = frame.expiresAtHostMs, (0...Wire.maximumCounter).contains(expiry),
            let revision = frame.expectedRevision, (0...Wire.maximumCounter).contains(revision),
            let action = frame.action, let fields = commands[action.kind],
            let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
            let rawAction = object["action"] as? [String: Any]
        else { throw invalid("Invalid command.") }
        let rootFields: Set<String> = [
            "version", "type", "command_id", "host_epoch", "expires_at_host_ms", "expected_revision", "action",
        ]
        guard Set(object.keys) == rootFields, Set(rawAction.keys) == fields else {
            throw invalid("The command contains unexpected or missing fields.")
        }
        switch action.kind {
        case "queue.enqueue", "queue.play_now", "queue.play_next":
            guard let song = action.song, Wire.validate(song),
                let object = rawAction["song"] as? [String: Any],
                Set(object.keys) == Set(["source", "id"])
            else { throw invalid("Invalid song identity.") }
            if let occurrence = action.occurrenceId, !Wire.isIdentifier(occurrence) {
                throw invalid("Invalid playback occurrence.")
            }
        case "queue.remove", "queue.move":
            guard let entry = action.entryId, Wire.isIdentifier(entry) else { throw invalid("Invalid queue request.") }
            if let anchor = action.beforeEntryId, !Wire.isIdentifier(anchor) { throw invalid("Invalid queue anchor.") }
        case "playback.volume":
            guard let percent = action.percent, (0...100).contains(percent) else { throw invalid("Invalid volume.") }
        default:
            guard let occurrence = action.occurrenceId, Wire.isIdentifier(occurrence) else {
                throw invalid("The action must identify the current playback occurrence.")
            }
            if action.kind == "playback.seek" {
                guard let position = action.positionMs, (0...Wire.maximumCounter).contains(position) else {
                    throw invalid("Invalid playback position.")
                }
            }
        }
    }

    private static func invalid(_ message: String) -> CadenzaError {
        .failure("invalid_command", message)
    }
}
