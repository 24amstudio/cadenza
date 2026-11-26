import Network
import Testing

@testable import CadenzaHost

struct CastSnapshotTests {
    private func device(_ name: String, display: CastDisplay) -> CastDiscovery.Device {
        CastDiscovery.Device(
            name: name, display: display,
            endpoint: .service(name: name, type: "_googlecast._tcp", domain: "local.", interface: nil))
    }

    @Test func devicesCarryTheirDisplayClassAndThePresentationModeTravelsAsAWireValue() {
        let snapshot = CastSnapshot.make(
            devices: [device("Living Room TV", display: .display), device("Kitchen speaker", display: .none)],
            presentation: .fullSuite, transmit: .idle)

        #expect(snapshot.presentation == "full_suite")
        #expect(
            snapshot.devices == [
                CastSnapshot.Device(name: "Living Room TV", display: "display"),
                CastSnapshot.Device(name: "Kitchen speaker", display: "none"),
            ])
    }

    @Test func theDeviceListStopsAtTheProtocolLimit() {
        let devices = (1...40).map { device("Device \($0)", display: .unknown) }
        let snapshot = CastSnapshot.make(devices: devices, presentation: .auto, transmit: .idle)

        #expect(snapshot.devices.count == CastSnapshot.deviceLimit)
    }

    @Test func aFailedTransmissionReportsItsDeviceAndReason() {
        let snapshot = CastSnapshot.make(
            devices: [], presentation: .auto, transmit: .failed(device: "Kitchen speaker", reason: "Refused"))

        #expect(
            snapshot.transmit == CastSnapshot.Transmit(state: "failed", device: "Kitchen speaker", reason: "Refused"))
    }
}
