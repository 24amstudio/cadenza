import Foundation

/// Where the karaoke lyrics are shown: in the Sing window on this Mac, or on a Cast device. The two are exclusive, so
/// the lyrics are never drawn in both places.
enum VideoOutputTarget: String, Sendable, Codable {
    case hostDisplay = "host_display"
    case castTransmitter = "cast_transmitter"

    static let defaultsKey = "videoOutputTarget"

    static func stored(in defaults: UserDefaults = .standard) -> VideoOutputTarget {
        defaults.string(forKey: defaultsKey).flatMap(VideoOutputTarget.init(rawValue:)) ?? .hostDisplay
    }
}
