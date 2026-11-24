import Testing

@testable import CadenzaHost

struct CastSnapshotTests {
    @Test func devicesCarryTheirDisplayClassAndThePresentationModeTravelsAsAWireValue() {
        let snapshot = CastSnapshot.make(
            devices: [
                CastDiscovery.Device(name: "Living Room TV", display: .display),
                CastDiscovery.Device(name: "Kitchen speaker", display: .none),
            ],
            presentation: .fullSuite)

        #expect(snapshot.presentation == "full_suite")
        #expect(
            snapshot.devices == [
                CastSnapshot.Device(name: "Living Room TV", display: "display"),
                CastSnapshot.Device(name: "Kitchen speaker", display: "none"),
            ])
    }

    @Test func theDeviceListStopsAtTheProtocolLimit() {
        let devices = (1...40).map { CastDiscovery.Device(name: "Device \($0)", display: .unknown) }
        let snapshot = CastSnapshot.make(devices: devices, presentation: .auto)

        #expect(snapshot.devices.count == CastSnapshot.deviceLimit)
    }
}
