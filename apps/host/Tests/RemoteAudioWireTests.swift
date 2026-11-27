import Foundation
import Testing

@testable import CadenzaHost

struct RemoteAudioWireTests {
    /// The shared fixture is the source of truth for every decoder, so these tests read it instead of copying bytes.
    private func fixture() throws -> [String: Any] {
        // apps/host/Tests/<file> is four levels below the repository root.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/protocol/examples/remote-audio-frames.json")
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func hex(_ value: Any?) throws -> String {
        let entry = try #require(value as? [String: Any])
        return try #require(entry["hex"] as? String)
    }

    private func bytes(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        return data
    }

    @Test func audioFrameEncodesToTheSharedFixtureBytes() throws {
        let fixture = try fixture()
        let payload = RemoteAudioWire.littleEndianPayload(int16: [1000, -1000, 2000, -2000])
        let frame = RemoteAudioWire.AudioFrame(
            flag: .crossoverHPFMains, channels: 2, bitDepth: .int16, sequenceNumber: 42,
            hostCaptureTimeUs: 1_000_000_123_456, targetPlayoutHostUs: 1_000_028_123_456, frameCount: 2,
            payload: payload)

        let encoded = try #require(RemoteAudioWire.encode(frame))
        let expected = try hex(fixture["audioFrame"])
        #expect(encoded == bytes(expected))
        #expect(encoded.count == RemoteAudioWire.audioHeaderBytes + 8)
    }

    @Test func controlFramesEncodeToTheSharedFixtureBytes() throws {
        let fixture = try fixture()
        #expect(RemoteAudioWire.flush(generation: 7) == bytes(try hex(fixture["flush"])))
        #expect(
            RemoteAudioWire.ping(sequence: 3, t1HostSendUs: 1_000_000_123_456)
                == bytes(try hex(fixture["ping"])))
    }

    @Test func pongFromTheRemoteDecodesItsThreeTimestamps() throws {
        let pong = try #require(RemoteAudioWire.pong(bytes(try hex(try fixture()["pong"]))))
        #expect(pong.t1HostSendUs == 1_000_000_123_456)
        #expect(pong.t2RemoteRecvUs == 5_000_000_250_000)
        #expect(pong.t3RemoteSendUs == 5_000_000_260_000)
        #expect(RemoteAudioWire.pong(Data(repeating: 0x05, count: 24)) == nil)
    }

    @Test func frameWithAPayloadThatDoesNotMatchItsHeaderIsRefused() {
        let short = RemoteAudioWire.AudioFrame(
            flag: .pureFullRange, channels: 2, bitDepth: .float32, sequenceNumber: 1,
            hostCaptureTimeUs: 0, targetPlayoutHostUs: 0, frameCount: 4, payload: Data(count: 8))
        #expect(RemoteAudioWire.encode(short) == nil)

        let threeChannels = RemoteAudioWire.AudioFrame(
            flag: .pureFullRange, channels: 3, bitDepth: .float32, sequenceNumber: 1,
            hostCaptureTimeUs: 0, targetPlayoutHostUs: 0, frameCount: 1, payload: Data(count: 12))
        #expect(RemoteAudioWire.encode(threeChannels) == nil)
    }

    @Test func float32SamplesKeepTheirExactBitsOnTheWire() {
        let samples: [Float] = [0.1234567, -0.9999999, 1e-30, 0.5]
        let payload = samples.withUnsafeBufferPointer { RemoteAudioWire.littleEndianPayload(float: $0) }
        let decoded: [Float] = (0..<samples.count).map { index in
            let raw = payload.subdata(in: index * 4..<index * 4 + 4).withUnsafeBytes {
                UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
            }
            return Float(bitPattern: raw)
        }
        #expect(decoded == samples)
    }
}
