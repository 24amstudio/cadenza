import Foundation
import Testing

@testable import CadenzaHost

/// A capture that never produces audio. The fan-out test needs only the transport messages, not a Music tap.
private final class SilentCapture: SingCaptureRoute, @unchecked Sendable {
    var format: SingAudioFormat? { nil }
    var isAvailable: Bool { false }
    func start(_ receive: @escaping @Sendable (SingAudioBuffer) -> Void) async throws {}
    func stop() {}
}

@MainActor
struct CastStageFanOutTests {
    /// The contract's budget for a transport fan-out, measured on the Host from the command to the last send.
    static let fanOutBudget = Duration.milliseconds(15)

    @Test func aTransportFanOutReachesEveryApprovedReceiverWithinTheBudget() {
        let hub = StageHub(receivers: StageReceivers(file: nil))
        var sent: [Int: [Data]] = [:]
        for index in 0..<8 {
            let session = StageHub.Session(
                id: "s\(index)", role: "tv_stage",
                send: { payload, _ in
                    sent[index, default: []].append(payload)
                    return true
                },
                close: {})
            session.isApproved = true
            hub.attach(session)
        }
        let coordinator = StageCoordinator(
            hub: hub, audio: StageAudioTransmitter(hub: hub, capture: SilentCapture()), suites: StageSuiteStore())

        let start = ContinuousClock.now
        coordinator.transportDispatched(isPlaying: false, targetPositionMs: 42_000)
        let elapsed = ContinuousClock.now - start

        #expect(elapsed < Self.fanOutBudget)
        #expect(sent.count == 8)
        #expect(
            sent.values.allSatisfy { messages in
                messages.count == 1 && String(decoding: messages[0], as: UTF8.self).contains("OPTIMISTIC_STATE")
            })
    }
}
