import Foundation
import Testing

@testable import CadenzaHost

struct CastStageProtocolTests {
    private func profile(_ overrides: [String: Any] = [:]) -> Data {
        var object: [String: Any] = [
            "version": 1, "type": "RECEIVER_PROFILE", "receiverId": "tv-living-room-01",
            "transportType": "cadenza_web_tv_stage", "displayName": "Living Room TV", "hasDisplay": true,
            "isStandby": false, "isTouchSupported": false, "maxAudioChannels": 6,
            "supportedCodecs": ["aac", "ac-3", "pcm"], "lipSyncOffsetMs": 0,
        ]
        for (key, value) in overrides { object[key] = value }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func aValidProfileParsesWithItsCodecsAndTransport() throws {
        let parsed = try #require(StageReceiverProfile.parse(profile()))
        #expect(parsed.receiverId == "tv-living-room-01")
        #expect(parsed.transport == .webStage)
        #expect(parsed.supportedCodecs == ["aac", "ac-3", "pcm"])
        #expect(parsed.receiverToken == nil)
    }

    @Test func anUnknownFieldOrTypeOrCodecIsRefused() {
        #expect(StageReceiverProfile.parse(profile(["requestedBy": "remote"])) == nil)
        #expect(StageReceiverProfile.parse(profile(["type": "RECEIVER_STATUS"])) == nil)
        #expect(StageReceiverProfile.parse(profile(["supportedCodecs": ["ac-3", "ac-3"]])) == nil)
        #expect(StageReceiverProfile.parse(profile(["supportedCodecs": ["widevine"]])) == nil)
        #expect(StageReceiverProfile.parse(profile(["supportsWidevineL1": true])) == nil)
    }

    @Test func outOfRangeValuesAreRefused() {
        #expect(StageReceiverProfile.parse(profile(["maxAudioChannels": 9])) == nil)
        #expect(StageReceiverProfile.parse(profile(["lipSyncOffsetMs": 251])) == nil)
        #expect(StageReceiverProfile.parse(profile(["displayName": ""])) == nil)
        #expect(StageReceiverProfile.parse(Data("not json".utf8)) == nil)
    }

    @Test func aTokenMustBeThirtyTwoToOneHundredTwentyEightURLSafeCharacters() {
        let token = String(repeating: "a", count: 32)
        #expect(StageReceiverProfile.parse(profile(["receiverToken": token]))?.receiverToken == token)
        #expect(StageReceiverProfile.parse(profile(["receiverToken": "short"])) == nil)
        #expect(StageReceiverProfile.parse(profile(["receiverToken": String(repeating: "a", count: 31) + "/"])) == nil)
    }

    @Test func aReceiverOnlyMatchesTheRoleItConnectedWith() throws {
        let web = try #require(StageReceiverProfile.parse(profile()))
        let android = try #require(
            StageReceiverProfile.parse(profile(["transportType": "cadenza_android_tv_receiver"])))
        #expect(web.matches(role: "tv_stage"))
        #expect(!web.matches(role: "android_tv_receiver"))
        #expect(android.matches(role: "android_tv_receiver"))
    }

    @Test func pairingAndAcceptedMessagesCarryTheirFields() throws {
        let pairing = try #require(
            JSONSerialization.jsonObject(with: StageMessage.pairing(pin: "0427", expiresInMs: 300_000))
                as? [String: Any])
        #expect(pairing["type"] as? String == "STAGE_PAIRING")
        #expect(pairing["pin"] as? String == "0427")
        #expect(pairing["expiresInMs"] as? Int == 300_000)
        let accepted = try #require(
            JSONSerialization.jsonObject(with: StageMessage.accepted(token: "tok")) as? [String: Any])
        #expect(accepted["receiverToken"] as? String == "tok")
    }
}
