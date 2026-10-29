import XCTest
@testable import CadenzaHost

final class TransportNegotiationTests: XCTestCase {
    private func path(_ name: String, rtt: Int64, loss: Double) -> TransportPathStatus {
        TransportPathStatus(
            transport: name,
            state: "connected",
            rssiDbm: nil,
            rttMs: rtt,
            lossPercent: loss,
            throughputKbps: 1_000,
            backlogBytes: 0,
            energyPercentPerHour: name == "ble" ? 0.5 : 2,
            energyConfidence: "high",
            sampleAgeMs: 0,
            p95RttMs: rtt,
            reconnects: 0,
            activeRemotes: 1)
    }

    func testBothSidesHardLimitsExcludeAPath() {
        var host = HostTransportPolicy()
        host.constraints.maximumLossPercent = 5
        let decision = TransportNegotiator.decide(
            host: host,
            remote: nil,
            remotePreference: .reliability,
            remoteConstraints: TransportConstraints(maximumLossPercent: 1),
            paths: [path("ble", rtt: 50, loss: 2), path("lan", rtt: 5, loss: 0)])
        XCTAssertEqual(decision.selected, "lan")
        XCTAssertTrue(decision.reason.contains("within Host limits"))
    }

    func testManualPathIsVisibleAndHonoredWhenHealthy() {
        var host = HostTransportPolicy()
        host.manualPath = "ble"
        let decision = TransportNegotiator.decide(
            host: host,
            remote: nil,
            remotePreference: .latency,
            paths: [path("ble", rtt: 50, loss: 0), path("lan", rtt: 5, loss: 0)])
        XCTAssertEqual(decision.selected, "ble")
        XCTAssertEqual(decision.policyMode, "manual")
    }
}
