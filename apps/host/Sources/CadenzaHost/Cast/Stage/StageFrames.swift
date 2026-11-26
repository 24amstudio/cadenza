import Foundation

/// Binary frames for stage receivers. Integers are big-endian. `shared/protocol/README.md` defines the layout, and
/// `shared/protocol/examples/cast-stage-frames.json` holds the bytes that every decoder must accept.
enum StageFrame {
    static let maximumPayloadBytes = 65_536
    static let audioType: UInt8 = 0x01
    static let flushType: UInt8 = 0x02
    static let initType: UInt8 = 0x03

    enum Codec: UInt8, Sendable, Equatable {
        case ac3FMP4 = 1
        /// Reserved by the contract. The Host never produces it, because browser support is inconsistent.
        case flacFMP4 = 2
        case lpcmRaw = 3
        case aacFMP4 = 4
    }

    enum SampleRate: UInt8, Sendable, Equatable {
        case hz48000 = 1
        case hz44100 = 2

        init?(hertz: Double) {
            switch Int(hertz) {
            case 48_000: self = .hz48000
            case 44_100: self = .hz44100
            default: return nil
            }
        }

        var hertz: Int {
            switch self {
            case .hz48000: 48_000
            case .hz44100: 44_100
            }
        }
    }

    /// One audio frame. Returns nil when the channel count or payload size is outside the contract.
    static func audio(
        codec: Codec, channels: Int, sampleRate: SampleRate, presentationTimeUs: UInt64, payload: Data
    ) -> Data? {
        guard (1...8).contains(channels), payload.count <= maximumPayloadBytes else { return nil }
        var frame = Data([audioType, codec.rawValue, UInt8(channels), sampleRate.rawValue])
        frame.append(bigEndian: presentationTimeUs)
        frame.append(bigEndian: UInt32(payload.count))
        frame.append(payload)
        return frame
    }

    /// The fragmented MP4 `ftyp` and `moov` boxes that a receiver appends before any fragment.
    static func initSegment(codec: Codec, channels: Int, sampleRate: SampleRate, payload: Data) -> Data? {
        guard (1...8).contains(channels), payload.count <= maximumPayloadBytes else { return nil }
        var frame = Data([initType, codec.rawValue, UInt8(channels), sampleRate.rawValue])
        frame.append(bigEndian: UInt32(payload.count))
        frame.append(payload)
        return frame
    }

    /// Tells the receiver to drop everything buffered before this generation.
    static func flush(generation: UInt32) -> Data {
        var frame = Data([flushType])
        frame.append(bigEndian: generation)
        return frame
    }
}

extension Data {
    fileprivate mutating func append<Value: FixedWidthInteger>(bigEndian value: Value) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
