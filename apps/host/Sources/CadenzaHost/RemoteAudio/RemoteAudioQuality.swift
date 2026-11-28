import Foundation

enum RemoteAudioQuality: Int, Comparable, Sendable, CaseIterable {
    case compact = 0
    case standard = 1
    case lossless = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var bitDepth: RemoteAudioWire.BitDepth {
        self == .lossless ? .int24 : .int16
    }

    var channels: UInt8 {
        self == .compact ? 1 : 2
    }

    var wireName: String {
        switch self {
        case .lossless: "lossless_24_48"
        case .standard: "standard_16_48"
        case .compact: "compact_16_48_mono"
        }
    }

    var payloadBitsPerSecond: Int {
        48_000 * Int(channels) * bitDepth.bytesPerSample * 8
    }
}
