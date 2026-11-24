import Foundation
import Testing

@testable import CadenzaHost

struct CastCapabilityTests {
    @Test func aSpeakerWithoutVideoOutputIsAudioOnlyAndAMissingRecordNeedsAProbe() {
        #expect(CastDisplay.fromCapabilities("0") == CastDisplay.none)
        #expect(CastDisplay.fromCapabilities("1") == CastDisplay.display)
        #expect(CastDisplay.fromCapabilities("5") == CastDisplay.display)
        #expect(CastDisplay.fromCapabilities(nil) == CastDisplay.unknown)
        #expect(CastDisplay.fromCapabilities("not a number") == CastDisplay.unknown)
    }

    @Test func thePresentationModeOnlyChoosesTheSuiteWhenAScreenIsKnown() {
        #expect(CastRouting.output(for: .auto, display: .display) == .fullSuite)
        #expect(CastRouting.output(for: .auto, display: .none) == .audio)
        #expect(CastRouting.output(for: .auto, display: .unknown) == .audio)
        #expect(CastRouting.output(for: .fullSuite, display: .none) == .audio)
        #expect(CastRouting.output(for: .fullSuite, display: .display) == .fullSuite)
        #expect(CastRouting.output(for: .audioOnly, display: .display) == .audio)
    }
}
