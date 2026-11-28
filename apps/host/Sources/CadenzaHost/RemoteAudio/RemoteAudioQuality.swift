import Foundation

enum RemoteAudioQuality: Int, Comparable, Sendable, CaseIterable {
    case standard = 0
    case lossless = 1

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var bitDepth: RemoteAudioWire.BitDepth {
        self == .lossless ? .int24 : .int16
    }

    var channels: UInt8 { 2 }

    var wireName: String {
        switch self {
        case .lossless: "lossless_24_48"
        case .standard: "standard_16_48"
        }
    }

    var payloadBitsPerSecond: Int {
        48_000 * Int(channels) * bitDepth.bytesPerSample * 8
    }
}
