import Foundation

/// The Google Cast devices, the presentation mode, and the transmission state a Remote can show. Audio is sent only while
/// a transmission is active.
struct CastSnapshot: Codable, Equatable, Sendable {
    struct Device: Codable, Equatable, Sendable {
        var name: String
        var display: String
    }

    struct Transmit: Codable, Equatable, Sendable {
        var state: String
        var device: String?
        var reason: String?
    }

    static let deviceLimit = 32

    var presentation: String
    var devices: [Device]
    var transmit: Transmit?

    static func make(
        devices: [CastDiscovery.Device],
        presentation: CastPresentationMode,
        transmit: CastTransmitter.State
    ) -> CastSnapshot {
        CastSnapshot(
            presentation: presentation.wireName,
            devices: devices.prefix(deviceLimit).map { Device(name: $0.name, display: $0.display.wireName) },
            transmit: transmit.snapshot)
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

extension CastTransmitter.State {
    var snapshot: CastSnapshot.Transmit {
        switch self {
        case .idle:
            CastSnapshot.Transmit(state: "idle", device: nil, reason: nil)
        case .starting(let device):
            CastSnapshot.Transmit(state: "starting", device: device, reason: nil)
        case .transmitting(let device):
            CastSnapshot.Transmit(state: "transmitting", device: device, reason: nil)
        case .failed(let device, let reason):
            CastSnapshot.Transmit(state: "failed", device: device, reason: reason)
        }
    }
}
