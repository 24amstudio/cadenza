import AVFAudio
import XCTest
import os
@testable import CadenzaHost

final class SingAudioTests: XCTestCase {
    func testDefaultBackendIsProcessSafeStereoFallback() {
        XCTAssertEqual(SingSeparatorFactory.defaultBackend().backend, "stereo-center")
    }

    func testCoordinatorRejectsASeparatorThatCannotPrimeForLivePlayback() async {
        let coordinator = await SingCoordinator(
            route: SingTestRoute(),
            separator: SingTestSeparator(latencyMs: 1_001),
            output: SingTestOutput())
        await coordinator.prepare(for: "occurrence")
        let session = await coordinator.session
        XCTAssertEqual(session.status, "failed")
        XCTAssertEqual(session.issue, "The Sing model takes too long to prime for live playback.")
    }

    func testCoordinatorCanRetryAfterASeparatorPreparationFailure() async throws {
        let separator = RetryingSingTestSeparator()
        let coordinator = await SingCoordinator(
            route: SingTestRoute(), separator: separator, output: SingTestOutput())

        await coordinator.prepare(for: "occurrence")
        let failed = await coordinator.session
        XCTAssertEqual(failed.status, "failed")
        await coordinator.prepare(for: "occurrence")
        let ready = await coordinator.session
        XCTAssertEqual(ready.status, "ready")
    }

    func testStemMixerPreservesInstrumentalAtZeroAndClipsOutput() {
        XCTAssertEqual(SingStemMixer.render(mix: 0.4, vocal: 0.2, vocalPercent: 0), 0.2, accuracy: 0.0001)
        XCTAssertEqual(SingStemMixer.render(mix: 0.4, vocal: 0.2, vocalPercent: 100), 0.4, accuracy: 0.0001)
        XCTAssertEqual(SingStemMixer.render(mix: 1, vocal: -1, vocalPercent: 0), 1, accuracy: 0.0001)
    }

    func testCaptureBufferPoolReturnsAReleasedBufferAndBoundsCapacity() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let pool = SingAudioBufferPool(format: format, capacity: 4, count: 1)
        let first = try XCTUnwrap(pool.acquire(frameCount: 2))
        XCTAssertNil(pool.acquire(frameCount: 5))
        XCTAssertNil(pool.acquire(frameCount: 2))
        first.lease.release()
        let second = try XCTUnwrap(pool.acquire(frameCount: 2))
        second.lease.release()
    }

    func testStereoFallbackSuppressesCenteredSignalAtZeroVocalMix() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
        input.frameLength = 2
        input.floatChannelData![0][0] = 0.5
        input.floatChannelData![0][1] = -0.5
        input.floatChannelData![1][0] = 0.5
        input.floatChannelData![1][1] = -0.5
        let buffer = SingAudioBuffer(
            format: SingAudioFormat(sampleRate: 48_000, channelCount: 2), frameCount: 2, samples: input)
        let output = try StereoCenterSuppressor().process(buffer, vocalPercent: 0)
        XCTAssertEqual(output.samples.floatChannelData![0][0], 0, accuracy: 0.0001)
        XCTAssertEqual(output.samples.floatChannelData![1][0], 0, accuracy: 0.0001)
    }

    func testStereoFallbackPreservesSignalAtFullVocalMix() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        input.frameLength = 1
        input.floatChannelData![0][0] = 0.25
        input.floatChannelData![1][0] = -0.75
        let buffer = SingAudioBuffer(
            format: SingAudioFormat(sampleRate: 48_000, channelCount: 2), frameCount: 1, samples: input)
        let output = try StereoCenterSuppressor().process(buffer, vocalPercent: 100)
        XCTAssertEqual(output.samples.floatChannelData![0][0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(output.samples.floatChannelData![1][0], -0.75, accuracy: 0.0001)
    }
}

private final class SingTestRoute: SingCaptureRoute, @unchecked Sendable {
    let format: SingAudioFormat? = SingAudioFormat(sampleRate: 48_000, channelCount: 2)
    let isAvailable = true

    func start(_ receive: @escaping @Sendable (SingAudioBuffer) -> Void) async throws {}

    func stop() {}
}

private final class SingTestSeparator: SingSeparator, @unchecked Sendable {
    let backend = "test"
    let modelRevision = "test-1"
    let latencyMs: Int64

    init(latencyMs: Int64) {
        self.latencyMs = latencyMs
    }

    func prepare(format: SingAudioFormat) async throws -> Int64 { latencyMs }

    func process(_ input: SingAudioBuffer, vocalPercent: Int) throws -> SingAudioBuffer { input }
}

private final class RetryingSingTestSeparator: SingSeparator, @unchecked Sendable {
    let backend = "test-retry"
    let modelRevision = "test-retry-1"
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    private var attempts = 0

    func prepare(format: SingAudioFormat) async throws -> Int64 {
        let attempt = lock.withLock { _ in
            attempts += 1
            return attempts
        }
        if attempt == 1 { throw SingAudioError.unavailable("temporary model failure") }
        return 0
    }

    func process(_ input: SingAudioBuffer, vocalPercent: Int) throws -> SingAudioBuffer { input }
}

private final class SingTestOutput: SingOutputSink, @unchecked Sendable {
    var onFailure: (@Sendable (String) -> Void)?

    func start(format: SingAudioFormat) throws {}

    func enqueue(_ buffer: SingAudioBuffer) {}

    func stop() {}
}
