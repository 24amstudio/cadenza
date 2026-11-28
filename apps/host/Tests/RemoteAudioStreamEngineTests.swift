import AVFAudio
import Darwin
import Foundation
import XCTest

@testable import CadenzaHost

/// The Remote places each frame from its playout time, so the engine must stamp blocks by device time. A consumer that
/// wakes late and drains several blocks at once must not collapse their playout times onto one instant.
final class RemoteAudioStreamEngineTests: XCTestCase {
    func testBlocksDrainedTogetherKeepTheirDeviceSpacing() async throws {
        let route = ScriptedCaptureRoute()
        let engine = RemoteAudioStreamEngine(capture: route)
        let frames = FrameLog()
        let delivered = DispatchSemaphore(value: 0)

        let config = RemoteAudioStreamConfig(
            enabled: true, streamMode: .pureTransferExclusive, targetClientId: "remote-a")
        try await engine.start(
            config: config, remoteOffsetUs: 20_000, localOffsetUs: 0, calibration: nil
        ) { frame in
            frames.append(frame)
            delivered.signal()
        }

        // Three blocks, one block of device time apart, handed over at once as a late consumer receives them.
        let start = mach_absolute_time()
        let blockTicks = try Self.ticks(forFrames: 512)
        for index in 0..<3 {
            route.emit(try Self.block(hostTime: start + UInt64(index) * blockTicks))
        }
        for _ in 0..<3 {
            XCTAssertEqual(delivered.wait(timeout: .now() + 2), .success)
        }
        engine.stop()

        let playout = frames.playoutTimes
        XCTAssertEqual(playout.count, 3)
        for (earlier, later) in zip(playout, playout.dropFirst()) {
            // 512 frames at 48 kHz is 10 667 µs, give or take the rounding of each block's continuous-clock time.
            XCTAssertLessThanOrEqual(abs(Int64(later) - Int64(earlier) - 10_667), 1)
        }
    }

    func testBlocksCapturedBeforeAFlushAreNotDeliveredAfterIt() async throws {
        let route = ScriptedCaptureRoute()
        let engine = RemoteAudioStreamEngine(capture: route)
        let events = EventLog()
        let config = RemoteAudioStreamConfig(
            enabled: true, streamMode: .pureTransferExclusive, targetClientId: "remote-a")
        try await engine.start(config: config, remoteOffsetUs: 20_000, localOffsetUs: 0, calibration: nil) { frame in
            events.record("frame \(frame.sequenceNumber)")
        }
        let fiveMsTicks = try Self.ticks(forFrames: 240)

        route.emit(try Self.block(hostTime: mach_absolute_time()))
        engine.flush { events.record("flushed") }
        route.emit(try Self.block(hostTime: mach_absolute_time() - fiveMsTicks))
        route.emit(try Self.block(hostTime: mach_absolute_time()))

        events.waitForCount(3)
        try await Task.sleep(for: .milliseconds(200))
        engine.stop()
        XCTAssertEqual(events.all, ["frame 0", "flushed", "frame 1"])
    }

    func testAGlideKeepsConsecutiveFramesWithinOneStepOfEachOther() async throws {
        let route = ScriptedCaptureRoute()
        let engine = RemoteAudioStreamEngine(capture: route)
        let frames = FrameLog()
        let delivered = DispatchSemaphore(value: 0)
        let config = RemoteAudioStreamConfig(
            enabled: true, streamMode: .pureTransferExclusive, targetClientId: "remote-a")
        try await engine.start(config: config, remoteOffsetUs: 20_000, localOffsetUs: 0, calibration: nil) { frame in
            frames.append(frame)
            delivered.signal()
        }

        let start = mach_absolute_time()
        let blockTicks = try Self.ticks(forFrames: 512)
        let blockCount = 200
        for index in 0..<blockCount {
            if index == 3 {
                engine.update(config: config, remoteOffsetUs: 30_000, localGoalUs: 0)
            }
            route.emit(try Self.block(hostTime: start + UInt64(index) * blockTicks))
        }
        for _ in 0..<blockCount {
            XCTAssertEqual(delivered.wait(timeout: .now() + 2), .success)
        }
        engine.stop()

        let received = frames.received
        XCTAssertEqual(received.count, blockCount)
        XCTAssertTrue(received.contains { $0.frameCount != 512 }, "the glide must stretch blocks")
        let oneStepUs = OffsetSlew.maximumStepSamples * 1_000_000 / 48_000 + 1
        for (earlier, later) in zip(received, received.dropFirst()) {
            let earlierEnd = Double(earlier.targetPlayoutHostUs) + Double(earlier.frameCount) * 1_000_000 / 48_000
            XCTAssertLessThanOrEqual(abs(Double(later.targetPlayoutHostUs) - earlierEnd), oneStepUs)
        }
        let first = try XCTUnwrap(received.first)
        let last = try XCTUnwrap(received.last)
        XCTAssertEqual(Int64(first.targetPlayoutHostUs) - Int64(first.hostCaptureTimeUs), 20_000)
        XCTAssertEqual(Int64(last.targetPlayoutHostUs) - Int64(last.hostCaptureTimeUs), 30_000)
    }

    private static func ticks(forFrames frames: Int) throws -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanoseconds = Double(frames) / 48_000 * 1_000_000_000
        return UInt64(nanoseconds * Double(timebase.denom) / Double(timebase.numer))
    }

    private static func block(hostTime: UInt64) throws -> SingAudioBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let samples = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        samples.frameLength = 512
        return SingAudioBuffer(
            format: SingAudioFormat(sampleRate: 48_000, channelCount: 2), frameCount: 512, samples: samples,
            hostTime: hostTime)
    }
}

/// Holds the capture callback so the test decides when each block arrives.
private final class ScriptedCaptureRoute: SingCaptureRoute, @unchecked Sendable {
    private var receive: (@Sendable (SingAudioBuffer) -> Void)?

    var format: SingAudioFormat? { SingAudioFormat(sampleRate: 48_000, channelCount: 2) }
    var isAvailable: Bool { true }

    func start(_ receive: @escaping @Sendable (SingAudioBuffer) -> Void) async throws {
        self.receive = receive
    }

    func stop() {
        receive = nil
    }

    func emit(_ buffer: SingAudioBuffer) {
        receive?(buffer)
    }
}

/// Collects the frames the engine delivers. The engine calls `deliver` on its own queue.
private final class FrameLog: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [RemoteAudioWire.AudioFrame] = []

    func append(_ frame: RemoteAudioWire.AudioFrame) {
        lock.lock()
        defer { lock.unlock() }
        frames.append(frame)
    }

    var playoutTimes: [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return frames.map(\.targetPlayoutHostUs)
    }

    var received: [RemoteAudioWire.AudioFrame] {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private let arrivals = DispatchSemaphore(value: 0)
    private var events: [String] = []

    func record(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
        arrivals.signal()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func waitForCount(_ count: Int) {
        for _ in 0..<count where arrivals.wait(timeout: .now() + 2) != .success {
            return
        }
    }
}
