import Foundation
import Testing

@testable import CadenzaHost

struct CastStageCodecTests {
    private func profile(codecs: [String], channels: Int) throws -> StageReceiverProfile {
        let object: [String: Any] = [
            "version": 1, "type": "RECEIVER_PROFILE", "receiverId": "tv", "transportType": "cadenza_web_tv_stage",
            "displayName": "TV", "hasDisplay": true, "isStandby": false, "isTouchSupported": false,
            "maxAudioChannels": channels, "supportedCodecs": codecs,
        ]
        return try #require(StageReceiverProfile.parse(try JSONSerialization.data(withJSONObject: object)))
    }

    @Test func stereoUsesAACWhenTheReceiverPlaysIt() throws {
        let route = StageCodecPlan.route(
            sourceChannels: 2, profile: try profile(codecs: ["aac", "pcm"], channels: 2), format: .transcodeAuto,
            ac3Encoder: true)
        #expect(route == .aac)
    }

    @Test func fiveOneUsesAC3OnlyWhenTheEncoderAndReceiverBothSupportIt() throws {
        let full = try profile(codecs: ["aac", "ac-3", "pcm"], channels: 6)
        #expect(
            StageCodecPlan.route(sourceChannels: 6, profile: full, format: .transcodeAuto, ac3Encoder: true) == .ac3)
        #expect(
            StageCodecPlan.route(sourceChannels: 6, profile: full, format: .transcodeAuto, ac3Encoder: false) == .aac)
    }

    @Test func aStereoReceiverGetsAFoldedSurroundSource() throws {
        let stereo = try profile(codecs: ["aac"], channels: 2)
        #expect(
            StageCodecPlan.route(sourceChannels: 12, profile: stereo, format: .transcodeAuto, ac3Encoder: true) == .aac)
    }

    @Test func survivalBudgetLimitsEveryReceiverToStereoWithoutAC3() throws {
        let fiveOne = try profile(codecs: ["aac", "ac-3", "pcm"], channels: 6)
        #expect(
            StageCodecPlan.route(
                sourceChannels: 6, profile: fiveOne, format: .transcodeAuto, ac3Encoder: true, stereoOnly: true) == .aac
        )
    }

    @Test func bitstreamSendsRawPCMAtTheReceiversChannelCount() throws {
        let fiveOne = try profile(codecs: ["pcm"], channels: 6)
        let stereo = try profile(codecs: ["pcm"], channels: 2)
        #expect(
            StageCodecPlan.route(sourceChannels: 6, profile: fiveOne, format: .bitstream, ac3Encoder: true)
                == .lpcm(channels: 6))
        #expect(
            StageCodecPlan.route(sourceChannels: 8, profile: fiveOne, format: .bitstream, ac3Encoder: true)
                == .lpcm(channels: 6))
        #expect(
            StageCodecPlan.route(sourceChannels: 6, profile: stereo, format: .bitstream, ac3Encoder: true)
                == .lpcm(channels: 2))
    }

    @Test func noRouteExistsForAnUnsupportedSourceOrAReceiverWithoutACodec() throws {
        let aacOnly = try profile(codecs: ["aac"], channels: 2)
        #expect(
            StageCodecPlan.route(sourceChannels: 4, profile: aacOnly, format: .transcodeAuto, ac3Encoder: true) == nil)
        #expect(StageCodecPlan.route(sourceChannels: 2, profile: aacOnly, format: .bitstream, ac3Encoder: true) == nil)
    }
}
