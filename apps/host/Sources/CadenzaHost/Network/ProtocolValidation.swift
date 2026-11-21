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
        "playback.shuffle": ["kind", "enabled"],
        "playback.repeat": ["kind", "mode"],
        "sing.enable": ["kind", "occurrence_id"],
        "sing.disable": ["kind", "occurrence_id"],
        "sing.mix": ["kind", "occurrence_id", "vocal_percent"],
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
            "pair", "hello", "clock", "search", "search.suggest", "browse.get", "song.prepare", "operation.cancel",
            "lyrics.get",
            "analytics.ack",
            "state.get", "command.status", "remote.configure", "log.report", "artwork.get", "artwork.cancel",
            "motion.get",
            "transport.configure", "session.status", "host.update",
            "recommendation.passport", "recommendation.query", "recommendation.feedback", "recommendation.plan",
            "recommendation.shadow_observation",
        ].contains(frame.type) {
            throw invalid("Unknown message type.")
        }
        if let requestId = frame.requestId, !Wire.isIdentifier(requestId) {
            throw invalid("Invalid request identifier.")
        }
        if let query = frame.query, query.count > 200 { throw invalid("Search is limited to 200 characters.") }
        if frame.type == "host.update", !["check", "install"].contains(frame.updateAction) {
            throw invalid("Unsupported Host update action.")
        }
        try validateRecommendation(frame)
        return frame
    }

    private static func validateSession(_ type: String, object: [String: Any]) throws {
        let required: [String: Set<String>] = [
            "pair": ["pair"], "hello": ["auth"], "clock": ["clock"],
            "search": ["request_id", "query", "scope"], "search.suggest": ["request_id", "query"],
            "browse.get": ["request_id", "browse"],
            "song.prepare": ["request_id", "song"],
            "operation.cancel": ["request_id"], "lyrics.get": [], "analytics.ack": ["sequence"],
            "state.get": [], "command.status": ["command_id"],
            "remote.configure": ["name", "heartbeat", "request_id"],
            "transport.configure": ["transport"],
            "session.status": ["status"],
            "log.report": [],
            "artwork.get": ["request_id", "artwork_url"],
            "artwork.cancel": ["request_id"],
            "recommendation.passport": ["recommendation_passport"],
            "recommendation.query": ["recommendation_query"],
            "recommendation.feedback": ["recommendation_feedback"],
            "recommendation.plan": ["recommendation_plan"],
            "recommendation.shadow_observation": ["recommendation_shadow_observation"],
            "motion.get": ["request_id", "occurrence_id"],
            "host.update": ["update_action", "request_id"],
        ]
        guard let fields = required[type] else { throw invalid("Unknown message type.") }
        let keys = Set(object.keys)
        var optionalFields = Set(["version", "type", "request_id"])
        if type == "song.prepare" { optionalFields.insert("song_metadata") }
        if type == "artwork.get" {
            optionalFields.formUnion(["progressive", "motion", "occurrence_id", "preview_only"])
        }
        // log.report accepts either a batch or the single-entry fields, so the branch below checks which form arrived.
        if type == "log.report" { optionalFields.formUnion(["log_entries", "log_action", "log_level", "log_message"]) }
        guard keys.isSuperset(of: fields.union(["version", "type"])),
            keys.isSubset(of: fields.union(optionalFields))
        else {
            throw invalid("The message contains unexpected or missing fields.")
        }
        if type == "pair" {
            try nested(
                object["pair"], fields: ["name"],
                optional: ["secret", "pin", "heartbeat", "remote_version"])
        }
        if type == "log.report" {
            // A batch is the normal form. The single-entry fields remain accepted for Remotes that predate batching.
            let levels = ["debug", "info", "warning", "error"]
            if let batch = object["log_entries"] {
                guard let items = batch as? [[String: Any]], (1...100).contains(items.count),
                    items.allSatisfy({ item in
                        guard let level = item["level"] as? String, levels.contains(level),
                            let action = item["action"] as? String, (1...120).contains(action.count),
                            let message = item["message"] as? String, (1...2_000).contains(message.count)
                        else { return false }
                        return true
                    })
                else { throw invalid("Invalid log report.") }
            } else {
                guard let level = object["log_level"] as? String, levels.contains(level),
                    let action = object["log_action"] as? String, (1...120).contains(action.count),
                    let message = object["log_message"] as? String, (1...2_000).contains(message.count)
                else { throw invalid("Invalid log report.") }
            }
        }
        if type == "artwork.get" {
            guard let value = object["artwork_url"] as? String, ArtworkProvider.isServableURL(value) else {
                throw invalid("Invalid artwork address.")
            }
            if object["progressive"] != nil, !(object["progressive"] is Bool) {
                throw invalid("Invalid artwork request.")
            }
            if object["motion"] != nil, !(object["motion"] is Bool) {
                throw invalid("Invalid artwork request.")
            }
            if object["preview_only"] != nil, !(object["preview_only"] is Bool) {
                throw invalid("Invalid artwork request.")
            }
            if object["motion"] as? Bool == true,
                !((object["occurrence_id"] as? String).map(Wire.isIdentifier) ?? false)
            {
                throw invalid("Motion artwork needs the song's playback occurrence.")
            }
        }
        if type == "hello" {
            try nested(
                object["auth"], fields: ["remote_id", "token", "last_credit_sequence"],
                optional: ["name", "heartbeat", "remote_version", "remote_build"])
        }
        if type == "clock" { try nested(object["clock"], fields: ["sent_at_remote_ms"]) }
        if type == "transport.configure" {
            try nested(
                object["transport"],
                fields: ["mode", "selection"],
                optional: ["primary", "bulk", "manual", "minimum_dwell_ms"])
            if let transport = object["transport"] as? [String: Any],
                let manual = transport["manual"] as? String,
                !["lan", "ble", "auto"].contains(manual)
            {
                throw invalid("Invalid manual transport.")
            }
        }
        if type == "session.status" {
            try nested(
                object["status"],
                fields: ["reported_at_ms", "device", "paths"],
                optional: ["power", "resources", "preference", "constraints", "effective"])
            if let status = object["status"] as? [String: Any],
                let constraints = status["constraints"] as? [String: Any]
            {
                try nested(
                    constraints,
                    fields: [],
                    optional: [
                        "maximum_latency_ms", "maximum_loss_percent", "require_reliable",
                        "minimum_reliability_percent",
                    ])
                if let latency = constraints["maximum_latency_ms"] { try counter(latency) }
                for key in ["maximum_loss_percent", "minimum_reliability_percent"] {
                    if let value = constraints[key] as? NSNumber, value.doubleValue.isFinite,
                        (0...100).contains(value.doubleValue)
                    {
                        continue
                    }
                    if constraints[key] != nil { throw invalid("Invalid transport constraint.") }
                }
            }
        }
        if type == "song.prepare" { try nested(object["song"], fields: ["source", "id"]) }
        if type == "browse.get" { try validateBrowse(object["browse"]) }
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
            guard let name = pair["name"] as? String, (1...80).contains(name.count),
                (pair["secret"] == nil) != (pair["pin"] == nil)
            else { throw invalid("Invalid pairing details.") }
            if let secret = pair["secret"] as? String, !(32...128).contains(secret.count) {
                throw invalid("Invalid pairing secret.")
            }
            if let pin = pair["pin"] as? String,
                pin.count != 4 || !pin.unicodeScalars.allSatisfy({ (48...57).contains($0.value) })
            {
                throw invalid("Invalid pairing PIN.")
            }
        }
        if let clock = object["clock"] as? [String: Any] { try counter(clock["sent_at_remote_ms"]) }
        if type == "analytics.ack" { try counter(object["sequence"]) }
        if type == "command.status" {
            guard let id = object["command_id"] as? String, Wire.isIdentifier(id) else {
                throw invalid("Invalid command identifier.")
            }
        }
        if type.hasPrefix("recommendation.") {
            guard keys.count <= 5 else { throw invalid("The recommendation message contains unexpected fields.") }
        }
    }

    // A browse request names playlists alone, one playlist, or an album or artist by exactly one of catalog ID or song. An
    // artist may instead be named by its text.
    private static func validateBrowse(_ value: Any?) throws {
        try nested(value, fields: ["kind"], optional: ["id", "song", "artist_name"])
        guard let browse = value as? [String: Any], let kind = browse["kind"] as? String else {
            throw invalid("Invalid browse request.")
        }
        let id = browse["id"]
        let song = browse["song"]
        let name = browse["artist_name"]
        func matches(_ pattern: String) -> Bool {
            (id as? String)?.range(of: pattern, options: .regularExpression) != nil
        }
        guard name == nil || kind == "artist" else { throw invalid("Only an artist can be named by its text.") }
        switch kind {
        case "playlists":
            guard id == nil, song == nil else { throw invalid("Playlists take no identifier.") }
        case "playlist":
            guard song == nil, matches("^[0-9A-F]{16}$") else { throw invalid("Invalid playlist.") }
        case "album", "artist":
            if let name {
                guard kind == "artist", id == nil, song == nil, let text = name as? String,
                    (1...200).contains(text.count)
                else { throw invalid("Invalid artist name.") }
                return
            }
            guard (id == nil) != (song == nil) else { throw invalid("Name the item by one of ID or song.") }
            if id != nil {
                guard matches("^[1-9][0-9]{0,19}$") else { throw invalid("Invalid catalog ID.") }
            } else {
                try nested(song, fields: ["source", "id"])
                let identity = song as? [String: Any]
                guard let source = identity?["source"] as? String, let songId = identity?["id"] as? String,
                    Wire.validate(SongIdentity(source: source, id: songId))
                else { throw invalid("Invalid song identity.") }
            }
        default:
            throw invalid("Choose an album, artist, or playlist.")
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
        case "playback.shuffle":
            guard let flag = rawAction["enabled"] as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else {
                throw invalid("Invalid shuffle setting.")
            }
        case "playback.repeat":
            guard let mode = action.mode, ["off", "one", "all"].contains(mode) else {
                throw invalid("Invalid repeat mode.")
            }
        case "sing.mix":
            guard let occurrence = action.occurrenceId, Wire.isIdentifier(occurrence),
                let vocalPercent = action.vocalPercent, (0...100).contains(vocalPercent)
            else { throw invalid("Invalid Sing mix.") }
        case "sing.enable", "sing.disable":
            guard let occurrence = action.occurrenceId, Wire.isIdentifier(occurrence) else {
                throw invalid("The Sing action must identify the current playback occurrence.")
            }
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

    private static func validateRecommendation(_ frame: Frame) throws {
        switch frame.type {
        case "recommendation.passport":
            guard let passport = frame.recommendationPassport,
                passport.payloadBase64.count <= CREEConstants.maximumPayloadBytes * 2,
                passport.publicKeyBase64.count <= 512, passport.signatureBase64.count <= 512
            else { throw invalid("Invalid recommendation passport.") }
        case "recommendation.query":
            guard
                let query = frame.recommendationQuery,
                (1...CREEConstants.maximumPlanHorizon).contains(query.horizon),
                query.modelVersion > 0
            else { throw invalid("Invalid recommendation query.") }
        case "recommendation.feedback":
            guard let feedback = frame.recommendationFeedback,
                Wire.isIdentifier(feedback.recommendationId), feedback.occurredAtMs >= 0
            else { throw invalid("Invalid recommendation feedback.") }
        case "recommendation.plan":
            guard let plan = frame.recommendationPlan,
                Wire.isIdentifier(plan.planId), Wire.isIdentifier(plan.recommendationId),
                plan.passportSequence > 0, plan.modelVersion > 0,
                (0...Wire.maximumCounter).contains(plan.expectedRevision),
                plan.operation.kind == "queue.play_next", let song = plan.operation.song, Wire.validate(song),
                plan.operation.entryId == nil, plan.operation.beforeEntryId == nil,
                plan.operation.occurrenceId == nil
            else { throw invalid("Invalid recommendation plan.") }
        case "recommendation.shadow_observation":
            guard
                let observation = frame.recommendationShadowObservation,
                Wire.isIdentifier(observation.observationId),
                observation.provenanceConfidence.isFinite,
                (0...1).contains(observation.provenanceConfidence),
                observation.observedAtMs >= 0
            else { throw invalid("Invalid recommendation shadow observation.") }
        default: break
        }
    }

    // A frame that fails to decode still answers the request or command it names. Only a valid identifier is echoed, so an
    // odd or oversized string from the peer never reaches the reply.
    static func rejection(of data: Data, message: String) -> Frame {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        func identifier(_ key: String) -> String? {
            guard let value = object?[key] as? String, Wire.isIdentifier(value) else { return nil }
            return value
        }
        if object?["type"] as? String == "command" {
            return Frame(
                type: "error", commandId: identifier("command_id"), errorCode: "invalid_command", message: message)
        }
        return Frame(
            type: "error", requestId: identifier("request_id"), errorCode: "invalid_command", message: message)
    }

    private static func invalid(_ message: String) -> CadenzaError {
        .failure("invalid_command", message)
    }
}
