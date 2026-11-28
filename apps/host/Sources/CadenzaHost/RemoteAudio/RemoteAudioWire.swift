import Foundation

/// Binary frames on the Wi-Fi Remote audio socket. `shared/protocol/README.md` defines the layouts, and
/// `shared/protocol/examples/remote-audio-frames.json` holds the bytes that every decoder must accept. Header integers
/// are big-endian. LPCM samples are little-endian.
enum RemoteAudioWire {
    static let audioType: UInt8 = 0x01
    static let flushType: UInt8 = 0x02
    static let pingType: UInt8 = 0x04
    static let pongType: UInt8 = 0x05
    static let audioHeaderBytes = 26
    static let pingBytes = 17
    static let pongBytes = 25

    enum StreamFlag: UInt8, Sendable, Equatable {
        case pureFullRange = 0
        case crossoverHPFMains = 1
    }

    enum BitDepth: UInt8, Sendable, Equatable {
        case int16 = 16
        case int24 = 24
        case float32 = 32

        var bytesPerSample: Int {
            switch self {
            case .int16: 2
            case .int24: 3
            case .float32: 4
            }
        }
    }

    struct AudioFrame: Equatable, Sendable {
        let flag: StreamFlag
        let channels: UInt8
        let bitDepth: BitDepth
        let sequenceNumber: UInt32
        let hostCaptureTimeUs: UInt64
        let targetPlayoutHostUs: UInt64
        let frameCount: UInt16
        /// Interleaved LPCM, little-endian, `frameCount × channels × bitDepth / 8` bytes.
        let payload: Data
    }

    /// The Remote's answer to a ping. Its three timestamps let the Host compute the offset.
    struct Pong: Equatable, Sendable {
        let t1HostSendUs: UInt64
        let t2RemoteRecvUs: UInt64
        let t3RemoteSendUs: UInt64
    }

    /// Encodes one audio frame. Returns nil when the channel count or the payload length does not match the header.
    static func encode(_ frame: AudioFrame) -> Data? {
        guard (1...2).contains(frame.channels) else { return nil }
        let expectedPayload = Int(frame.frameCount) * Int(frame.channels) * frame.bitDepth.bytesPerSample
        guard frame.payload.count == expectedPayload else { return nil }
        var data = Data(capacity: audioHeaderBytes + expectedPayload)
        data.append(audioType)
        data.append(frame.flag.rawValue)
        data.append(frame.channels)
        data.append(frame.bitDepth.rawValue)
        appendUInt(UInt64(frame.sequenceNumber), bytes: 4, to: &data)
        appendUInt(frame.hostCaptureTimeUs, bytes: 8, to: &data)
        appendUInt(frame.targetPlayoutHostUs, bytes: 8, to: &data)
        appendUInt(UInt64(frame.frameCount), bytes: 2, to: &data)
        data.append(frame.payload)
        return data
    }

    static func flush(generation: UInt32) -> Data {
        var data = Data([flushType])
        appendUInt(UInt64(generation), bytes: 4, to: &data)
        return data
    }

    /// A ping carries a sequence the Host can match, and the time the Host sent it.
    static func ping(sequence: UInt64, t1HostSendUs: UInt64) -> Data {
        var data = Data([pingType])
        appendUInt(sequence, bytes: 8, to: &data)
        appendUInt(t1HostSendUs, bytes: 8, to: &data)
        return data
    }

    /// Decodes a pong. Returns nil unless the frame is exactly 25 bytes with the pong type.
    static func pong(_ data: Data) -> Pong? {
        guard data.count == pongBytes, data[data.startIndex] == pongType else { return nil }
        return Pong(
            t1HostSendUs: readUInt(data, offset: 1, bytes: 8),
            t2RemoteRecvUs: readUInt(data, offset: 9, bytes: 8),
            t3RemoteSendUs: readUInt(data, offset: 17, bytes: 8))
    }

    /// Writes the PCM samples of one block as little-endian bytes.
    static func littleEndianPayload(float samples: UnsafeBufferPointer<Float>) -> Data {
        var data = Data(count: samples.count * 4)
        data.withUnsafeMutableBytes { raw in
            for (index, sample) in samples.enumerated() {
                raw.storeBytes(of: sample.bitPattern.littleEndian, toByteOffset: index * 4, as: UInt32.self)
            }
        }
        return data
    }

    static func littleEndianPayload(int16 samples: [Int16]) -> Data {
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { raw in
            for (index, sample) in samples.enumerated() {
                raw.storeBytes(of: sample.littleEndian, toByteOffset: index * 2, as: Int16.self)
            }
        }
        return data
    }

    private static func appendUInt(_ value: UInt64, bytes: Int, to data: inout Data) {
        for shift in stride(from: (bytes - 1) * 8, through: 0, by: -8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }

    private static func readUInt(_ data: Data, offset: Int, bytes: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<bytes {
            value = (value << 8) | UInt64(data[data.startIndex + offset + index])
        }
        return value
    }
}
