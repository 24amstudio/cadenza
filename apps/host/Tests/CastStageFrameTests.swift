import Foundation
import Testing

@testable import CadenzaHost

/// The stage byte contract is shared with the web and Android receivers through one fixture file.
enum StageFixtures {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "shared/protocol/examples/cast-stage-frames.json")

    static func frames() throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return root["frames"] as? [[String: Any]] ?? []
    }

    static func hex(_ bytes: Data) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    /// Encodes one fixture's documented fields with the Host encoder. Nil means the fixture is not a producible frame.
    static func produce(_ expect: [String: Any]) -> Data? {
        let codec = (expect["codec"] as? Int).flatMap { StageFrame.Codec(rawValue: UInt8($0)) }
        let channels = expect["channels"] as? Int ?? 0
        let payload = Data(hexString: expect["payloadHex"] as? String ?? "") ?? Data()
        switch expect["type"] as? String {
        case "AUDIO_FRAME":
            guard let codec,
                let rate = (expect["sampleRate"] as? Int).flatMap({ StageFrame.SampleRate(hertz: Double($0)) })
            else { return nil }
            let timestamp = UInt64(expect["presentationTimeUs"] as? Int ?? 0)
            return StageFrame.audio(
                codec: codec, channels: channels, sampleRate: rate, presentationTimeUs: timestamp, payload: payload)
        case "INIT_SEGMENT":
            guard let codec else { return nil }
            return StageFrame.initSegment(codec: codec, channels: channels, sampleRate: .hz48000, payload: payload)
        case "FLUSH_STREAM":
            return StageFrame.flush(generation: UInt32(expect["generationSeq"] as? Int ?? 0))
        default:
            return nil
        }
    }
}

struct CastStageFrameTests {
    @Test func everyProducibleFrameMatchesTheSharedFixture() throws {
        let fixtures = try StageFixtures.frames()
        let produced = fixtures.compactMap { fixture -> (String, String)? in
            guard let expect = fixture["expect"] as? [String: Any], let data = StageFixtures.produce(expect)
            else { return nil }
            return (fixture["name"] as? String ?? "", StageFixtures.hex(data))
        }
        #expect(produced.count == 5)
        for (name, hex) in produced {
            let expected = fixtures.first { $0["name"] as? String == name }?["hex"] as? String
            #expect(hex == expected, "\(name)")
        }
    }

    @Test func aFrameOutsideTheContractIsNotProduced() {
        let tooManyChannels = StageFrame.audio(
            codec: .aacFMP4, channels: 9, sampleRate: .hz48000, presentationTimeUs: 0, payload: Data([1]))
        let oversized = StageFrame.audio(
            codec: .aacFMP4, channels: 2, sampleRate: .hz48000, presentationTimeUs: 0,
            payload: Data(count: StageFrame.maximumPayloadBytes + 1))
        #expect(tooManyChannels == nil)
        #expect(oversized == nil)
        #expect(StageFrame.SampleRate(hertz: 32_000) == nil)
    }
}

extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes = Data()
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = bytes
    }
}
