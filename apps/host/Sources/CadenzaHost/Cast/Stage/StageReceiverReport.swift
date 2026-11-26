import Foundation

/// What a stage receiver reports about itself: what its output is playing, and its log lines. The Host shows the
/// playback next to what it sends and records the log lines. Neither changes what the Host sends.
enum StageReceiverReport: Equatable, Sendable {
    /// `channels` 0 means the receiver cannot tell the channel count of its output.
    case playback(codec: String, channels: Int, path: String, active: Bool)
    case log(level: HostLogLevel, message: String)

    static let codecs: Set<String> = ["aac", "ac3", "pcm"]
    static let maximumLogLength = 500

    static func parse(_ data: Data) -> StageReceiverReport? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["version"] as? Int == 1
        else { return nil }
        switch object["type"] as? String {
        case "STAGE_PLAYBACK":
            guard let codec = object["codec"] as? String, codecs.contains(codec),
                let channels = object["channels"] as? Int, (0...8).contains(channels),
                let path = object["path"] as? String, isPath(path),
                let active = object["active"] as? Bool
            else { return nil }

            return .playback(codec: codec, channels: channels, path: path, active: active)
        case "STAGE_LOG":
            guard let name = object["level"] as? String, let message = object["message"] as? String,
                !message.isEmpty, let level = logLevel(name)
            else { return nil }

            return .log(level: level, message: String(message.prefix(maximumLogLength)))
        default:
            return nil
        }
    }

    /// A short path name such as `mse` or `audiotrack_pcm`.
    private static func isPath(_ text: String) -> Bool {
        (1...32).contains(text.count)
            && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    private static func logLevel(_ name: String) -> HostLogLevel? {
        switch name {
        case "debug": .debug
        case "info": .info
        case "warn": .warning
        case "error": .error
        default: nil
        }
    }
}

/// The latest playback report a receiver sent. `unreported` until it sends one.
enum StagePlayback: Equatable, Sendable {
    case unreported
    case stopped
    case playing(CastSnapshot.Route, path: String)
}

/// Bounds how many log lines one receiver may record in a window, so a faulty receiver cannot flood the Host's log.
struct StageLogLimiter: Sendable {
    static let maximumPerWindow = 30
    static let window: TimeInterval = 10

    private var windowStart = Date.distantPast
    private var count = 0

    mutating func allow(now: Date) -> Bool {
        if now.timeIntervalSince(windowStart) >= Self.window {
            windowStart = now
            count = 0
        }
        guard count < Self.maximumPerWindow else { return false }
        count += 1

        return true
    }
}
