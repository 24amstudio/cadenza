import Foundation
import Testing

@testable import CadenzaHost

struct AudioFrameGateTests {
    @Test func sendsAFrameThatCanStillArriveBeforeItsPlayoutInstant() {
        var gate = AudioFrameGate()
        #expect(gate.admit(nowUs: 0, targetPlayoutUs: 10_000, inFlight: 0) == .send)
        #expect(gate.droppedStaleFrames60s(nowUs: 0) == 0)
    }

    @Test func dropsAFrameWhenTwoAreAlreadyUnacknowledged() {
        var gate = AudioFrameGate()
        #expect(gate.admit(nowUs: 0, targetPlayoutUs: 10_000, inFlight: 2) == .dropInFlightFull)
        #expect(gate.droppedStaleFrames60s(nowUs: 0) == 1)
    }

    @Test func dropsAFrameThatCannotLeaveWithTheMinimumTransportLead() {
        var gate = AudioFrameGate()
        // 4,000 µs of lead is required, so a frame due in 3,999 µs is already too late.
        #expect(gate.admit(nowUs: 0, targetPlayoutUs: 3_999, inFlight: 0) == .dropTooLate)
        #expect(gate.admit(nowUs: 0, targetPlayoutUs: 4_001, inFlight: 0) == .send)
    }

    @Test func degradesOnlyAfterSustainedDropsAboveTheRateLimit() {
        var gate = AudioFrameGate()
        // A Wi-Fi stall drops a frame every 30 ms, which is 33 a second, for 4 seconds.
        var now: UInt64 = 0
        while now < 4_000_000 {
            _ = gate.admit(nowUs: now, targetPlayoutUs: now, inFlight: 2)
            now += 30_000
        }
        #expect(gate.isDegraded(nowUs: now) == true)
    }

    @Test func aShortBurstOfDropsDoesNotDegradeTheLink() {
        var gate = AudioFrameGate()
        var now: UInt64 = 0
        while now < 1_000_000 {
            _ = gate.admit(nowUs: now, targetPlayoutUs: now, inFlight: 2)
            now += 30_000
        }
        // The burst ends, and frames flow again.
        for step in 0..<200 {
            let time = now + UInt64(step) * 10_000
            _ = gate.admit(nowUs: time, targetPlayoutUs: time + 50_000, inFlight: 0)
        }
        #expect(gate.isDegraded(nowUs: now + 5_000_000) == false)
    }

    @Test func countsDropsOverOnlyTheLastMinute() {
        var gate = AudioFrameGate()
        _ = gate.admit(nowUs: 0, targetPlayoutUs: 0, inFlight: 2)
        _ = gate.admit(nowUs: 70_000_000, targetPlayoutUs: 0, inFlight: 2)
        #expect(gate.droppedStaleFrames60s(nowUs: 70_000_000) == 1)
    }
}

struct RemoteClockEstimatorTests {
    @Test func symmetricExchangeRecoversTheExactOffset() throws {
        var estimator = RemoteClockEstimator()
        let offset: UInt64 = 5_000_000
        let t1: UInt64 = 1_000_000
        let t2 = t1 + 1_500 + offset
        let added = estimator.add(t1: t1, t2: t2, t3: t2, t4: t1 + 3_000)
        let sample = try #require(added)
        #expect(sample.offsetUs == 5_000_000)
        #expect(sample.rttUs == 3_000)
    }

    @Test func theSmallestRoundTripWinsOverWiFiSpikes() throws {
        var estimator = RemoteClockEstimator()
        // A spiky exchange with a 40 ms return leg reports an offset 20 ms out.
        estimator.add(t1: 0, t2: 1_000 + 5_000_000, t3: 1_000 + 5_000_000, t4: 41_000)
        // A clean exchange has a 2 ms round trip and the true offset.
        estimator.add(t1: 2_000_000, t2: 2_001_000 + 5_000_000, t3: 2_001_000 + 5_000_000, t4: 2_002_000)
        let best = try #require(estimator.best)
        #expect(best.rttUs == 2_000)
        #expect(best.offsetUs == 5_000_000)
    }

    @Test func aSixtyMinuteEightyPpmSkewStaysWithinTwoTenthsOfAMillisecond() throws {
        // Simulated Remote clock: it runs 80 ppm fast and starts 5 s ahead. Each ping has independent one-way delays,
        // with 1 ms base and up to 400 µs of jitter on each leg.
        let skew = 80e-6
        let startOffset = 5_000_000.0
        var random = SeededRandom(seed: 42)
        var estimator = RemoteClockEstimator()
        var worstErrorUs = 0.0
        var hostUs: UInt64 = 0
        while hostUs < 3_600_000_000 {
            let outbound = 1_000 + random.next() * 400
            let inbound = 1_000 + random.next() * 400
            let remoteAtArrival = startOffset + Double(hostUs) + Double(hostUs) * skew + outbound
            let t1 = hostUs
            let t2 = UInt64(remoteAtArrival.rounded())
            let t3 = t2
            let t4 = hostUs + UInt64((outbound + inbound).rounded())
            estimator.add(t1: t1, t2: t2, t3: t3, t4: t4)
            hostUs += 2_000_000
            if hostUs > 180_000_000, let predicted = estimator.offsetUs(atHostUs: hostUs) {
                let trueOffset = startOffset + Double(hostUs) * skew
                worstErrorUs = max(worstErrorUs, abs(Double(predicted) - trueOffset))
            }
        }
        #expect(worstErrorUs < 200, "worst error \(worstErrorUs) µs")
        #expect(abs(estimator.driftPpm - 80) < 2, "drift \(estimator.driftPpm) ppm")
    }
}

struct SilentCalibrationEngineTests {
    @Test func electronicDeltaIsTheRemoteLatencyMinusTheHostLatency() {
        // The Remote reports 17 ms. The Host's 480-frame output latency at 48 kHz is 10 ms, so the delta is 7 ms.
        let delta = SilentCalibrationEngine.electronicDeltaMs(
            remoteBaseLatencyMs: 5, remoteOutputLatencyMs: 12, hostLatencyFrames: 480, sampleRate: 48_000)
        #expect(abs(delta - 7) < 0.0001)
    }

    @Test func acousticDelayIsRecoveredFromAnInjectedFifteenMillisecondPath() throws {
        let sampleRate = 48_000.0
        let frames = 48_000
        var mainsNoise = SeededRandom(seed: 7)
        var subNoise = SeededRandom(seed: 9)
        let mainsReference = mainsNoise.samples(count: frames)
        let subReference = subNoise.samples(count: frames)
        let delayFrames = Int((15.0 / 1_000 * sampleRate).rounded())
        // The microphone hears the mains 15 ms late and the sub without delay, at equal levels.
        var mic = [Float](repeating: 0, count: frames)
        for index in delayFrames..<frames {
            mic[index] = 0.5 * mainsReference[index - delayFrames] + 0.5 * subReference[index]
        }
        let delta = try #require(
            SilentCalibrationEngine.acousticDeltaMs(
                mic: mic, mainsReference: mainsReference, subReference: subReference, sampleRate: sampleRate))
        #expect(abs(delta - 15) < 0.3, "measured \(delta) ms")
    }

    @Test func aWindowShorterThanTheSearchRangeGivesNoEstimate() {
        var noise = SeededRandom(seed: 1)
        let short = noise.samples(count: 1_000)
        #expect(
            SilentCalibrationEngine.peakDelayMs(signal: short, reference: short, sampleRate: 48_000) == nil)
    }
}

struct RemoteAudioStreamConfigTests {
    private func json(_ text: String) -> Data {
        Data(text.utf8)
    }

    @Test func decodesACrossoverConfigAndKeepsItsBounds() throws {
        let config = try RemoteAudioStreamConfig.decode(
            json(
                """
                {"version":1,"type":"REMOTE_AUDIO_STREAM_CONFIG","enabled":true,"streamMode":"crossover_split",\
                "targetClientId":"web-remote-living-room","crossoverHz":160,"subGainDb":-12,"phaseInvert":true,\
                "manualDistanceOffsetMs":-50}
                """))
        #expect(config.streamMode == .crossoverSplit)
        #expect(config.crossoverHz == 160)
        #expect(config.subGainDb == -12)
        #expect(config.manualDistanceOffsetMs == -50)
    }

    @Test func refusesValuesOutsideTheBoundsUnknownFieldsAndUnknownModes() {
        let base = #""version":1,"type":"REMOTE_AUDIO_STREAM_CONFIG","enabled":true"#
        let refused = [
            #"{\#(base),"streamMode":"crossover_split","crossoverHz":39.9}"#,
            #"{\#(base),"streamMode":"crossover_split","subGainDb":12.5}"#,
            #"{\#(base),"streamMode":"pure_transfer_exclusive","manualDistanceOffsetMs":50.5}"#,
            #"{\#(base),"streamMode":"stereo_wide"}"#,
            #"{\#(base),"streamMode":"pure_transfer_mirror","volume":0.5}"#,
            #"{\#(base),"streamMode":"crossover_split","crossoverHz":"80"}"#,
        ]
        for text in refused {
            #expect(throws: RemoteAudioStreamConfig.DecodeError.self) {
                try RemoteAudioStreamConfig.decode(json(text))
            }
        }
    }
}

/// A deterministic generator, so the simulations and the noise references are the same on every run.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }

    /// A value in [0, 1).
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }

    mutating func samples(count: Int) -> [Float] {
        (0..<count).map { _ in Float(next() * 2 - 1) }
    }
}
