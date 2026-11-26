import Network
import Testing

@testable import CadenzaHost

struct CastSnapshotTests {
    private func device(_ name: String, label: String? = nil, display: CastDisplay) -> CastDiscovery.Device {
        CastDiscovery.Device(
            name: name, label: label ?? name, display: display,
            endpoint: .service(name: name, type: "_googlecast._tcp", domain: "local.", interface: nil))
    }

    @Test func devicesCarryTheirDisplayClassAndThePresentationModeTravelsAsAWireValue() {
        let snapshot = CastSnapshot.make(
            devices: [device("Living Room TV", display: .display), device("Kitchen speaker", display: .none)],
            presentation: .fullSuite, transmit: .idle)

        #expect(snapshot.presentation == "full_suite")
        #expect(
            snapshot.devices == [
                CastSnapshot.Device(name: "Living Room TV", label: "Living Room TV", display: "display"),
                CastSnapshot.Device(name: "Kitchen speaker", label: "Kitchen speaker", display: "none"),
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

    @Test func theFriendlyNameIsPreferredAndTheInstanceIDIsOnlyTheLastResort() {
        let named = CastDiscovery.label(txt: ["fn": " Bedroom TV ", "md": "Smart TV"], instance: "Smart-TV-830c3b")
        let modelOnly = CastDiscovery.label(txt: ["md": "Smart TV"], instance: "Smart-TV-830c3b")
        let bare = CastDiscovery.label(txt: [:], instance: "Smart-TV-830c3b")

        #expect(named == "Bedroom TV")
        #expect(modelOnly == "Smart TV")
        #expect(bare == "Smart-TV-830c3b")
    }

    @Test func aTransmissionIsIdentifiedByTheDeviceIDButDescribedByItsLabel() {
        let snapshot = CastSnapshot.make(
            devices: [device("Smart-TV-830c3b", label: "Bedroom TV", display: .unknown)],
            presentation: .auto,
            transmit: .transmitting(device: "Smart-TV-830c3b"),
            transmitRoute: CastSnapshot.Route(codec: "aac", channels: 2))

        #expect(
            snapshot.devices == [CastSnapshot.Device(name: "Smart-TV-830c3b", label: "Bedroom TV", display: "unknown")])
        #expect(snapshot.transmit?.device == "Smart-TV-830c3b")
        #expect(snapshot.transmit?.status?.text.hasSuffix("→ Bedroom TV (Unknown)") == true)
    }
}
