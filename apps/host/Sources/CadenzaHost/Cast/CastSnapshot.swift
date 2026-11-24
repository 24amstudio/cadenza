import Foundation

/// The Google Cast devices and presentation mode a Remote can show. Audio is not sent to these devices yet.
struct CastSnapshot: Codable, Equatable, Sendable {
    struct Device: Codable, Equatable, Sendable {
        var name: String
        var display: String
    }

    static let deviceLimit = 32

    var presentation: String
    var devices: [Device]

    static func make(devices: [CastDiscovery.Device], presentation: CastPresentationMode) -> CastSnapshot {
        CastSnapshot(
            presentation: presentation.wireName,
            devices: devices.prefix(deviceLimit).map { Device(name: $0.name, display: $0.display.wireName) })
    }
}

extension CastPresentationMode {
    var wireName: String {
        switch self {
        case .auto: "auto"
        case .audioOnly: "audio_only"
        case .fullSuite: "full_suite"
        }
    }
}

extension CastDisplay {
    var wireName: String {
        switch self {
        case .none: "none"
        case .display: "display"
        case .unknown: "unknown"
        }
    }
}
