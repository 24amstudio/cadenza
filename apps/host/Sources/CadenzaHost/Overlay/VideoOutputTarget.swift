import Foundation

/// Where a music video's karaoke line is shown: over Music's window on this Mac, or on a Cast device. The two are
/// exclusive, so one line is never drawn in both places.
enum VideoOutputTarget: String, Sendable, Codable {
    case hostDisplay = "host_display"
    case castTransmitter = "cast_transmitter"

    static let defaultsKey = "videoOutputTarget"

    static func stored(in defaults: UserDefaults = .standard) -> VideoOutputTarget {
        defaults.string(forKey: defaultsKey).flatMap(VideoOutputTarget.init(rawValue:)) ?? .hostDisplay
    }
}
