import Foundation

/// How the Mac sends to Google Cast devices. Auto uses the richest output each device supports.
enum CastPresentationMode: String, CaseIterable, Sendable {
    case auto, audioOnly, fullSuite

    var title: String {
        switch self {
        case .auto: "Auto (Recommended)"
        case .audioOnly: "Audio Only"
        case .fullSuite: "Full Cadenza Suite"
        }
    }
}

/// What a Cast device can show, from the `ca` capability bitmask in its mDNS record. VIDEO_OUT is bit 0x0001.
enum CastDisplay: Sendable, Equatable {
    case none
    case display
    /// No readable capability record. A runtime probe of the device must decide, so it is treated as audio for now.
    case unknown

    var label: String {
        switch self {
        case .none: "Audio only"
        case .display: "Screen"
        case .unknown: "Checking"
        }
    }

    static func fromCapabilities(_ value: String?) -> CastDisplay {
        guard let value, let bits = Int(value) else { return .unknown }
        return bits & 0x0001 != 0 ? .display : .none
    }
}

extension CastPresentationMode {
    static let defaultsKey = "castPresentationMode"

    /// The mode the listener chose in Settings. Auto is the default when nothing is stored or the stored value is unknown.
    static func stored() -> CastPresentationMode {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(CastPresentationMode.init(rawValue:)) ?? .auto
    }
}
