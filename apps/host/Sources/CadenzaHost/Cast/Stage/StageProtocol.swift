import Foundation

/// The JSON that stage receivers send and receive. Parsing mirrors `shared/protocol/v1/cast.schema.json`: unknown fields,
/// out-of-range values, and unknown types are refused before any receiver state changes.
struct StageReceiverProfile: Equatable, Sendable {
    enum Transport: String, Sendable {
        case webStage = "cadenza_web_tv_stage"
        case androidTV = "cadenza_android_tv_receiver"
    }

    static let allowedCodecs: Set<String> = ["aac", "ac-3", "ec-3", "flac", "pcm"]
    private static let allowedKeys: Set<String> = [
        "version", "type", "receiverId", "transportType", "displayName", "hasDisplay", "isStandby",
        "isTouchSupported", "maxAudioChannels", "supportedCodecs", "lipSyncOffsetMs", "receiverToken",
    ]

    let receiverId: String
    let transport: Transport
    let displayName: String
    let hasDisplay: Bool
    let isStandby: Bool
    let isTouchSupported: Bool
    let maxAudioChannels: Int
    let supportedCodecs: Set<String>
    let lipSyncOffsetMs: Int
    let receiverToken: String?

    /// Returns nil for any message that is not a valid `RECEIVER_PROFILE`.
    static func parse(_ data: Data) -> StageReceiverProfile? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys).isSubset(of: allowedKeys),
            object["version"] as? Int == 1, object["type"] as? String == "RECEIVER_PROFILE",
            let receiverId = boundedString(object["receiverId"], maximum: 80),
            let transport = (object["transportType"] as? String).flatMap(Transport.init(rawValue:)),
            let displayName = boundedString(object["displayName"], maximum: 80),
            let hasDisplay = object["hasDisplay"] as? Bool,
            let isStandby = object["isStandby"] as? Bool,
            let isTouchSupported = object["isTouchSupported"] as? Bool,
            let channels = object["maxAudioChannels"] as? Int, (2...8).contains(channels),
            let codecs = object["supportedCodecs"] as? [String],
            (1...4).contains(codecs.count), Set(codecs).count == codecs.count,
            Set(codecs).isSubset(of: allowedCodecs)
        else { return nil }
        let offset = object["lipSyncOffsetMs"] as? Int ?? 0
        guard (0...250).contains(offset) else { return nil }
        let token: String?
        if let raw = object["receiverToken"] {
            guard let text = raw as? String, isToken(text) else { return nil }
            token = text
        } else {
            token = nil
        }
        return StageReceiverProfile(
            receiverId: receiverId, transport: transport, displayName: displayName, hasDisplay: hasDisplay,
            isStandby: isStandby, isTouchSupported: isTouchSupported, maxAudioChannels: channels,
            supportedCodecs: Set(codecs), lipSyncOffsetMs: offset, receiverToken: token)
    }

    /// A Tier-2 browser sends `cadenza_web_tv_stage` on `role=tv_stage`, and a Tier-3 receiver sends the other pair.
    func matches(role: String) -> Bool {
        switch (role, transport) {
        case ("tv_stage", .webStage), ("android_tv_receiver", .androidTV): true
        default: false
        }
    }

    private static func boundedString(_ value: Any?, maximum: Int) -> String? {
        guard let text = value as? String, !text.isEmpty, text.count <= maximum else { return nil }
        return text
    }

    /// Tokens are 32 to 128 URL-safe characters, as the schema states.
    static func isToken(_ text: String) -> Bool {
        (32...128).contains(text.count)
            && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

/// A playback command that a receiver sends from a TV remote key. Only an approved receiver may send one, and the Host
/// runs it as a normal playback command.
enum StageCommand {
    static let actions: Set<String> = ["playback.pause", "playback.resume", "playback.skip", "playback.previous"]

    /// The playback kind for a valid `STAGE_COMMAND`, or nil for anything else.
    static func kind(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys) == ["version", "type", "action"], object["version"] as? Int == 1,
            object["type"] as? String == "STAGE_COMMAND", let action = object["action"] as? String,
            actions.contains(action)
        else { return nil }
        return action
    }
}

/// Host-to-receiver messages. Each returns the UTF-8 JSON for one text frame.
enum StageMessage {
    static func pairing(pin: String, expiresInMs: Int) -> Data {
        encode(["version": 1, "type": "STAGE_PAIRING", "pin": pin, "expiresInMs": expiresInMs])
    }

    static func accepted(token: String) -> Data {
        encode(["version": 1, "type": "STAGE_ACCEPTED", "receiverToken": token])
    }

    static func trackSuite(_ suite: StageTrackSuite) -> Data {
        var object: [String: Any] = [
            "version": 1, "type": "TRACK_SUITE_PAYLOAD", "trackId": suite.trackId, "title": suite.title,
            "artist": suite.artist, "album": suite.album, "durationMs": suite.durationMs,
            "lines": suite.lines.map(\.json),
        ]
        if let quality = suite.quality { object["quality"] = quality }
        if let artworkUrl = suite.artworkUrl { object["artworkUrl"] = artworkUrl }
        if let motionUrl = suite.motionUrl { object["motionUrl"] = motionUrl }
        return encode(object)
    }

    static func prefetch(trackId: String, reason: String) -> Data {
        encode(["version": 1, "type": "PREFETCH_NEXT_SUITE", "trackId": trackId, "reason": reason])
    }

    static func optimisticState(
        isPlaying: Bool, targetPositionMs: Int64, playbackRate: Double, hostMonoTimeMs: Int64, audioLatencyMs: Int
    ) -> Data {
        encode([
            "version": 1, "type": "OPTIMISTIC_STATE", "isPlaying": isPlaying,
            "targetPositionMs": targetPositionMs, "playbackRate": playbackRate,
            "hostMonoTimeMs": hostMonoTimeMs, "audioLatencyMs": audioLatencyMs,
        ])
    }

    static func clockCalibrate(actualPositionMs: Int64, audioLatencyMs: Int, hostMonoTimeMs: Int64) -> Data {
        encode([
            "version": 1, "type": "CLOCK_CALIBRATE", "actualPositionMs": actualPositionMs,
            "audioLatencyMs": audioLatencyMs, "hostMonoTimeMs": hostMonoTimeMs,
        ])
    }

    static func videoKaraoke(mediaUrl: String, subtitleUrl: String, userOffsetMs: Int) -> Data {
        encode([
            "version": 1, "type": "VIDEO_KARAOKE_PAYLOAD", "source": "lan_mp4", "mediaUrl": mediaUrl,
            "subtitleUrl": subtitleUrl, "userOffsetMs": userOffsetMs,
        ])
    }

    private static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}
