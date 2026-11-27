import Foundation
import Testing

@testable import CadenzaHost

struct RoomCalibrationWindowTests {
    final class Counter: @unchecked Sendable {
        var count = 0
    }

    @Test func completesOnceWhenEveryStreamHasTwoSeconds() {
        let completions = Counter()
        // A 100 Hz rate makes the two-second window 200 frames, so the test stays small.
        let window = RoomCalibrationWindow(sampleRate: 100) { completions.count += 1 }

        window.appendMic(Array(repeating: 0.1, count: 150))
        window.appendReferences(mains: Array(repeating: 0.2, count: 150), sub: Array(repeating: 0.3, count: 150))
        #expect(window.completeWindow() == nil)

        window.appendMic(Array(repeating: 0.1, count: 500))
        window.appendReferences(mains: Array(repeating: 0.2, count: 500), sub: Array(repeating: 0.3, count: 500))
        window.appendMic(Array(repeating: 0.1, count: 500))

        let full = window.completeWindow()
        #expect(full?.mic.count == 200)
        #expect(full?.mains.count == 200)
        #expect(full?.sub.count == 200)
        #expect(completions.count == 1)
    }
}

struct OffsetSlewTests {
    @Test func glidesToItsGoalInHalfASecondWithEqualSteps() {
        var slew = OffsetSlew(current: 0)
        let blockMs = 512.0 / 48_000 * 1_000
        slew.setGoal(15_000, blockMs: blockMs)

        var previous = 0.0
        var largestStep = 0.0
        var steps = 0
        while slew.current != 15_000, steps < 200 {
            let value = slew.advance()
            largestStep = max(largestStep, value - previous)
            previous = value
            steps += 1
        }

        // 500 ms of 10.67 ms blocks is 47 steps, and each step is a 47th of the change.
        #expect(steps == 47)
        #expect(slew.current == 15_000)
        #expect(largestStep <= 15_000 / 47 + 1e-6)
    }

    @Test func aRepeatedGoalDoesNotRestartTheGlide() {
        var slew = OffsetSlew(current: 0)
        slew.setGoal(4_700, blockMs: 10)
        for _ in 0..<10 {
            _ = slew.advance()
        }
        // The same goal arrives again, as it does on every two-second timing tick, and the glide keeps its place.
        slew.setGoal(4_700, blockMs: 10)
        var remaining = 0
        while slew.current != 4_700, remaining < 100 {
            _ = slew.advance()
            remaining += 1
        }
        // A 500 ms glide of 10 ms blocks is 50 steps. Ten have run, so 40 are left.
        #expect(remaining == 40)
    }
}

struct AcousticAlignmentTests {
    @Test func aSignalThatLeadsItsReferenceGivesANegativeDelay() throws {
        var random = SeededRandom(seed: 3)
        let reference = random.samples(count: 48_000)
        let leadFrames = 480
        var microphone = [Float](repeating: 0, count: 48_000)
        for index in 0..<(48_000 - leadFrames) {
            microphone[index] = reference[index + leadFrames]
        }

        let measured = try #require(
            SilentCalibrationEngine.peakDelayMs(signal: microphone, reference: reference, sampleRate: 48_000))
        #expect(abs(measured + 10) < 0.3, "measured \(measured) ms")
    }

    @Test func aCommonCaptureOffsetCancelsOutOfTheAcousticDelta() throws {
        // The microphone and the references start 20 ms apart. That offset moves both peaks by the same amount, so the
        // difference still reads the 15 ms of path that the mains take beyond the sub.
        var random = SeededRandom(seed: 11)
        let mains = random.samples(count: 48_000)
        let sub = random.samples(count: 48_000)
        let common = 960
        let mainsDelay = 720 + common
        let subDelay = common
        var microphone = [Float](repeating: 0, count: 48_000)
        for index in mainsDelay..<48_000 {
            microphone[index] = 0.5 * mains[index - mainsDelay] + 0.5 * sub[index - subDelay]
        }

        let delta = try #require(
            SilentCalibrationEngine.acousticDeltaMs(
                mic: microphone, mainsReference: mains, subReference: sub, sampleRate: 48_000))
        #expect(abs(delta - 15) < 0.3, "measured \(delta) ms")
    }
}

@MainActor
struct RoomProfileStoreTests {
    @Test func aRoomOffsetIsSavedReplacedAndClearedWithinTheAllowedRange() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadenza-room-" + UUID().uuidString)
        let suite = "CadenzaTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try HostStore(directory: directory, defaults: defaults)
        let key = "synthetic-output|synthetic-browser"

        #expect(try store.roomAcousticOffsetUs(profileKey: key) == nil)
        try store.saveRoomAcousticOffsetUs(15_000, profileKey: key, measuredAtMs: 1)
        #expect(try store.roomAcousticOffsetUs(profileKey: key) == 15_000)
        try store.saveRoomAcousticOffsetUs(-2_500, profileKey: key, measuredAtMs: 2)
        #expect(try store.roomAcousticOffsetUs(profileKey: key) == -2_500)
        #expect(throws: CadenzaError.self) {
            try store.saveRoomAcousticOffsetUs(60_000, profileKey: key, measuredAtMs: 3)
        }
        try store.clearRoomProfile(profileKey: key)
        #expect(try store.roomAcousticOffsetUs(profileKey: key) == nil)
    }
}
