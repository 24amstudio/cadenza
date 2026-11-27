import Foundation

/// The three stream modes the Remote can select. The pure-transfer modes bypass the crossover completely.
enum RemoteAudioStreamMode: String, Sendable, Equatable, CaseIterable {
    case pureTransferExclusive = "pure_transfer_exclusive"
    case pureTransferMirror = "pure_transfer_mirror"
    case crossoverSplit = "crossover_split"

    var isPureTransfer: Bool {
        self != .crossoverSplit
    }
}

/// The Remote's `REMOTE_AUDIO_STREAM_CONFIG`. The bounds match `shared/protocol/v1/remote-audio.schema.json`, and a
/// value outside them is refused rather than clamped.
struct RemoteAudioStreamConfig: Equatable, Sendable {
    static let crossoverHzRange: ClosedRange<Double> = 40...160
    static let subGainDbRange: ClosedRange<Double> = -12...12
    static let distanceOffsetMsRange: ClosedRange<Double> = -50...50
    static let defaultCrossoverHz = 80.0
    static let allowedKeys: Set<String> = [
        "version", "type", "enabled", "streamMode", "targetClientId", "crossoverHz", "subGainDb", "phaseInvert",
        "manualDistanceOffsetMs",
    ]

    var enabled: Bool
    var streamMode: RemoteAudioStreamMode
    var targetClientId: String?
    var crossoverHz = defaultCrossoverHz
    var subGainDb = 0.0
    var phaseInvert = false
    var manualDistanceOffsetMs = 0.0

    enum DecodeError: Error, Equatable {
        case malformed
        case unknownField(String)
        case outOfRange(String)
    }

    /// Decodes and validates one config message. Unknown fields are refused, as the schema's `additionalProperties`
    /// requires.
    static func decode(_ data: Data) throws -> RemoteAudioStreamConfig {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodeError.malformed
        }
        if let unknown = object.keys.first(where: { !allowedKeys.contains($0) }) {
            throw DecodeError.unknownField(unknown)
        }
        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: data)
        } catch {
            throw DecodeError.malformed
        }
        guard wire.version == 1, wire.type == "REMOTE_AUDIO_STREAM_CONFIG",
            let mode = RemoteAudioStreamMode(rawValue: wire.streamMode)
        else { throw DecodeError.malformed }
        let config = RemoteAudioStreamConfig(
            enabled: wire.enabled, streamMode: mode, targetClientId: wire.targetClientId,
            crossoverHz: wire.crossoverHz ?? defaultCrossoverHz, subGainDb: wire.subGainDb ?? 0,
            phaseInvert: wire.phaseInvert ?? false, manualDistanceOffsetMs: wire.manualDistanceOffsetMs ?? 0)
        try config.validate()
        return config
    }

    /// The config as a `REMOTE_AUDIO_STREAM_CONFIG` message, the form that `decode` reads back.
    func message() -> Data {
        var object: [String: Any] = [
            "version": 1,
            "type": "REMOTE_AUDIO_STREAM_CONFIG",
            "enabled": enabled,
            "streamMode": streamMode.rawValue,
            "crossoverHz": crossoverHz,
            "subGainDb": subGainDb,
            "phaseInvert": phaseInvert,
            "manualDistanceOffsetMs": manualDistanceOffsetMs,
        ]
        if let targetClientId {
            object["targetClientId"] = targetClientId
        }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    func validate() throws {
        guard Self.crossoverHzRange.contains(crossoverHz) else { throw DecodeError.outOfRange("crossoverHz") }
        guard Self.subGainDbRange.contains(subGainDb) else { throw DecodeError.outOfRange("subGainDb") }
        guard Self.distanceOffsetMsRange.contains(manualDistanceOffsetMs) else {
            throw DecodeError.outOfRange("manualDistanceOffsetMs")
        }
    }

    private struct Wire: Decodable {
        let version: Int
        let type: String
        let enabled: Bool
        let streamMode: String
        let targetClientId: String?
        let crossoverHz: Double?
        let subGainDb: Double?
        let phaseInvert: Bool?
        let manualDistanceOffsetMs: Double?
    }
}
