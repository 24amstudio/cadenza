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

@MainActor
struct WifiSplitRemotesTests {
    @Test func onlyRemotesWithAConnectedWifiPathCanTakeTheMains() {
        let model = HostModel()
        let wifi = SessionStatus(
            reportedAtMs: 0, device: "Desk",
            paths: [TransportPathStatus(transport: "lan", state: "connected", rttMs: 8)])
        let bluetoothOnly = SessionStatus(
            reportedAtMs: 0, device: "Phone", paths: [TransportPathStatus(transport: "ble", state: "connected")])
        let wifiDown = SessionStatus(
            reportedAtMs: 0, device: "Tab", paths: [TransportPathStatus(transport: "lan", state: "disconnected")])
        model.connectedRemotes = [
            PairedRemote(id: "desk", name: "Desk", revoked: false, status: wifi),
            PairedRemote(id: "phone", name: "Phone", revoked: false, status: bluetoothOnly),
            PairedRemote(id: "tab", name: "Tab", revoked: false, status: wifiDown),
        ]

        #expect(model.wifiSplitRemotes.map(\.id) == ["desk"])
    }
}
