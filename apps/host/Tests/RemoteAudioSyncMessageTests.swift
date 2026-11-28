import Foundation
import Testing

@testable import CadenzaHost

struct RemoteAudioSyncMessageTests {
    private static let transmitting = RemoteAudioTelemetry(
        streamMode: .pureTransferMirror, calibrationState: "electronic_locked", electronicOffsetMs: 1.5,
        linkHealthy: true, transmitting: true, quality: .standard, qualityReason: .network)

    @Test func roundTripFieldsAreNullUntilTheFirstPong() {
        let message = RemoteAudioSyncMessage.make(
            telemetry: .idle, nowUs: 1_000, clock: RemoteClockEstimator(), jitterBufferMs: 28,
            droppedStaleFrames60s: 0)

        #expect(message["networkRttMs"] is NSNull)
        #expect(message["processingRttMs"] is NSNull)
        #expect(message["transmitting"] as? Bool == false)
    }

    @Test func roundTripFieldsCarryTheLatestExchangeInMilliseconds() {
        var clock = RemoteClockEstimator()
        clock.add(t1: 0, t2: 10_000, t3: 13_000, t4: 16_000)

        let message = RemoteAudioSyncMessage.make(
            telemetry: Self.transmitting, nowUs: 20_000, clock: clock, jitterBufferMs: 28, droppedStaleFrames60s: 0)

        #expect(message["networkRttMs"] as? Double == 13)
        #expect(message["processingRttMs"] as? Double == 3)
        #expect(message["transmitting"] as? Bool == true)
        #expect(message["quality"] as? String == "standard_16_48")
        #expect(message["qualityReason"] as? String == "network")
    }

    @Test func aNewerExchangeReplacesTheCurrentRoundTrip() {
        var clock = RemoteClockEstimator()
        clock.add(t1: 0, t2: 10_000, t3: 13_000, t4: 16_000)
        clock.add(t1: 2_000_000, t2: 2_000_500, t3: 2_000_700, t4: 2_002_000)

        let latest = clock.latest

        #expect(latest?.rttUs == 1_800)
        #expect(latest?.processingUs == 200)
        #expect(latest?.totalUs == 2_000)
    }

    @Test func aPongWhoseTurnaroundRunsBackwardsIsRejected() {
        var clock = RemoteClockEstimator()

        #expect(clock.add(t1: 0, t2: 10_000, t3: 9_000, t4: 16_000) == nil)
        #expect(clock.latest == nil)
    }
}
