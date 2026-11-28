import CoreAudio
import Foundation
import Testing

@testable import CadenzaHost

struct AudioOutputsTests {
    @Test func aTransportCodeNamesItsKindOfOutput() {
        #expect(AudioOutputs.transportName(kAudioDeviceTransportTypeAirPlay) == "airplay")
        #expect(AudioOutputs.transportName(kAudioDeviceTransportTypeBluetoothLE) == "bluetooth")
        #expect(AudioOutputs.transportName(0) == "other")
    }

    @Test func virtualAndAggregateOutputsAreLeftOutOfTheRemoteList() {
        let outputs = [
            AudioOutput(id: "speakers", name: "MacBook Air Speakers", transport: "built-in", isDefault: true),
            AudioOutput(id: "aggregate", name: "CADefaultDeviceAggregate", transport: "virtual", isDefault: false),
            AudioOutput(id: "zoom", name: "ZoomAudioDevice", transport: "virtual", isDefault: false),
            AudioOutput(id: "kitchen", name: "Kitchen", transport: "airplay", isDefault: false),
        ]

        #expect(AudioOutputs.remoteVisible(outputs).map(\.id) == ["speakers", "kitchen"])
    }

    @Test func anUnknownOutputIsNotSelectedAndTheListHasOneDefaultAtMost() {
        #expect(!AudioOutputs.select("no-such-output-\(UUID().uuidString)"))

        let outputs = AudioOutputs.current()

        #expect(outputs.filter(\.isDefault).count <= 1)
        #expect(outputs.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
    }
}
