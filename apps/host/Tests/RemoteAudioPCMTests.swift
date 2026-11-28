import Foundation
import Testing

@testable import CadenzaHost

struct RemoteAudioPCMTests {
    private static func readInt24(_ data: Data, sample index: Int) -> Float {
        let base = data.startIndex + index * 3
        let raw = UInt32(data[base]) | UInt32(data[base + 1]) << 8 | UInt32(data[base + 2]) << 16
        let signed = raw & 0x80_0000 != 0 ? Int32(bitPattern: raw | 0xFF00_0000) : Int32(raw)
        return Float(signed) / 8_388_607
    }

    private static func readInt16(_ data: Data, sample index: Int) -> Float {
        let base = data.startIndex + index * 2
        let raw = Int16(bitPattern: UInt16(data[base]) | UInt16(data[base + 1]) << 8)
        return Float(raw) / 32_767
    }

    @Test func twentyFourBitSamplesRoundTripToWithinOneStep() {
        let samples: [Float] = [0, 0.5, -0.5, 0.123_456, -0.987_654, 1, -1]
        let data = RemoteAudioPCM.littleEndian24(samples)

        #expect(data.count == samples.count * 3)
        for (index, sample) in samples.enumerated() {
            #expect(abs(Self.readInt24(data, sample: index) - sample) <= 1 / 8_388_607)
        }
    }

    @Test func sixteenBitSamplesRoundTripToWithinOneStep() {
        let samples: [Float] = [0, 0.25, -0.25, 0.777, -0.777]
        let data = RemoteAudioPCM.littleEndian16(samples)

        #expect(data.count == samples.count * 2)
        for (index, sample) in samples.enumerated() {
            #expect(abs(Self.readInt16(data, sample: index) - sample) <= 1 / 32_767)
        }
    }

    @Test func aHalfScaleSampleHasTheExpectedThreeBytes() {
        #expect(RemoteAudioPCM.littleEndian24([0.5]) == Data([0x00, 0x00, 0x40]))
        #expect(RemoteAudioPCM.littleEndian24([-1]) == Data([0x01, 0x00, 0x80]))
    }

    @Test func samplesOutsideFullScaleAreClampedNotWrapped() {
        let loud = RemoteAudioPCM.littleEndian16([4, -4])

        #expect(Self.readInt16(loud, sample: 0) == 1)
        #expect(Self.readInt16(loud, sample: 1) == -1)
    }

    @Test func aTwentyFourBitFrameEncodesWithItsDeclaredPayload() {
        let payload = RemoteAudioPCM.littleEndian24(Array(repeating: 0.1, count: 8))
        let frame = RemoteAudioWire.AudioFrame(
            flag: .pureFullRange, channels: 2, bitDepth: .int24, sequenceNumber: 0, hostCaptureTimeUs: 0,
            targetPlayoutHostUs: 0, frameCount: 4, payload: payload)

        #expect(RemoteAudioWire.encode(frame)?.count == 26 + 24)
    }
}
