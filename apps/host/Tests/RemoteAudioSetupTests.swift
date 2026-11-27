import Foundation
import Testing

@testable import CadenzaHost

struct RemoteAudioSetupStorageTests {
    @Test func aSavedSetupLoadsBackWithItsValues() throws {
        let suite = "CadenzaTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(RemoteAudioSetupStorage.load(defaults) == nil)

        var setup = RemoteAudioStreamConfig(enabled: true, streamMode: .crossoverSplit, targetClientId: "remote-a")
        setup.crossoverHz = 120
        setup.subGainDb = -3
        setup.phaseInvert = true
        setup.manualDistanceOffsetMs = 4.5
        RemoteAudioSetupStorage.save(setup, defaults: defaults)

        #expect(RemoteAudioSetupStorage.load(defaults) == setup)
    }
}
