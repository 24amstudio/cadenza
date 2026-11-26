import Foundation
import Testing

@testable import CadenzaHost

struct CastCapabilityTests {
    @Test func aSpeakerWithoutVideoOutputIsAudioOnlyAndAMissingRecordIsUnknown() {
        #expect(CastDisplay.fromCapabilities("0") == CastDisplay.none)
        #expect(CastDisplay.fromCapabilities("1") == CastDisplay.display)
        #expect(CastDisplay.fromCapabilities("5") == CastDisplay.display)
        #expect(CastDisplay.fromCapabilities(nil) == CastDisplay.unknown)
        #expect(CastDisplay.fromCapabilities("not a number") == CastDisplay.unknown)
    }

    @Test func stereoIsAACAndOnlySixChannelsUseAC3() {
        #expect(CastAudioCodec.forChannelCount(2) == .aac)
        #expect(CastAudioCodec.forChannelCount(6) == .ac3)
        #expect(CastAudioCodec.forChannelCount(8) == nil)
    }
}
