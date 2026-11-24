import AVFAudio
import Foundation

/// Encodes captured PCM to AAC-LC and wraps each packet in an ADTS header. Every ADTS frame stands alone, so a receiver
/// can start reading at any frame. Transcode (Auto) uses this path for stereo; multichannel audio is folded to stereo or
/// 5.1 before it reaches the encoder.
final class CastAACEncoder: @unchecked Sendable {
    static let bitRate = 256_000
    private static let samplingFrequencies: [Double] = [
        96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000,
    ]

    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let channels: Int
    private let samplingIndex: Int

    init?(sampleRate: Double, channels: Int, inputFormat: AVAudioFormat) {
        guard channels == 2 || channels == 6,
            let index = Self.samplingFrequencies.firstIndex(of: sampleRate),
            let output = AVAudioFormat(
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVEncoderBitRateKey: Self.bitRate,
                ]),
            let converter = AVAudioConverter(from: inputFormat, to: output)
        else { return nil }

        self.converter = converter
        outputFormat = output
        self.channels = channels
        samplingIndex = index
    }

    /// The ADTS frames for one captured buffer. The encoder keeps its own delay, so the first buffers may return none.
    func encode(_ input: AVAudioPCMBuffer) -> [[UInt8]] {
        let packets = AVAudioCompressedBuffer(
            format: outputFormat, packetCapacity: 32, maximumPacketSize: converter.maximumOutputPacketSize)
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: packets, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow

                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData

            return input
        }
        guard status != .error, packets.packetCount > 0, let descriptions = packets.packetDescriptions else { return [] }

        return (0..<Int(packets.packetCount)).map { index in
            let description = descriptions[index]
            let start = Int(description.mStartOffset)
            let size = Int(description.mDataByteSize)
            let payload = Array(UnsafeRawBufferPointer(
                start: packets.data.advanced(by: start), count: size))

            return adtsHeader(payloadLength: size) + payload
        }
    }

    private func adtsHeader(payloadLength: Int) -> [UInt8] {
        let frameLength = payloadLength + 7
        let profile = 1  // AAC-LC, stored as the profile minus one.
        return [
            0xFF,
            0xF1,
            UInt8((profile << 6) | (samplingIndex << 2) | (channels >> 2 & 0x1)),
            UInt8((channels & 0x3) << 6 | (frameLength >> 11 & 0x3)),
            UInt8((frameLength >> 3) & 0xFF),
            UInt8((frameLength & 0x7) << 5 | 0x1F),
            0xFC,
        ]
    }
}
