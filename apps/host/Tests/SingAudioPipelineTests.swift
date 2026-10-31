import AVFAudio
import XCTest
@testable import CadenzaHost

final class SingAudioPipelineTests: XCTestCase {
    func testPipelineProcessesBuffersOffCallbackAndStopsAcceptingAfterStop() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let samples = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        samples.frameLength = 1
        let input = SingAudioBuffer(
            format: SingAudioFormat(sampleRate: 48_000, channelCount: 2), frameCount: 1, samples: samples)
        let output = PipelineTestOutput()
        let pipeline = SingAudioPipeline(
            separator: PipelineTestSeparator(),
            output: output,
            mixState: SingMixState(),
            onFailure: { _ in XCTFail("The pass-through separator should not fail.") })

        let processed = expectation(description: "processed buffer")
        output.onEnqueue = { processed.fulfill() }
        pipeline.start()
        pipeline.submit(input)
        wait(for: [processed], timeout: 1)
        pipeline.stop()
        let count = output.count
        pipeline.submit(input)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(output.count, count)
    }

    func testPipelineFlushesStreamingSeparatorBeforeStoppingOutput() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let samples = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        samples.frameLength = 1
        let input = SingAudioBuffer(
            format: SingAudioFormat(sampleRate: 48_000, channelCount: 2), frameCount: 1, samples: samples)
        let output = PipelineTestOutput()
        let pipeline = SingAudioPipeline(
            separator: PipelineStreamingTestSeparator(),
            output: output,
            mixState: SingMixState(),
            onFailure: { _ in XCTFail("The streaming separator should not fail.") })

        pipeline.start()
        pipeline.submit(input)
        pipeline.stop()

        XCTAssertEqual(output.count, 1)
    }

    func testPipelineReportsStreamingFlushFailure() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let samples = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        samples.frameLength = 1
        let input = SingAudioBuffer(
            format: SingAudioFormat(sampleRate: 48_000, channelCount: 2), frameCount: 1, samples: samples)
        let output = PipelineTestOutput()
        let failure = expectation(description: "flush failure")
        let pipeline = SingAudioPipeline(
            separator: PipelineFailingFlushSeparator(),
            output: output,
            mixState: SingMixState(),
            onFailure: { _ in failure.fulfill() })

        pipeline.start()
        pipeline.submit(input)
        pipeline.stop()

        wait(for: [failure], timeout: 1)
        XCTAssertEqual(output.count, 0)
    }
}

private final class PipelineTestSeparator: SingSeparator, @unchecked Sendable {
    let backend = "test"
    let modelRevision = "test-1"

    func prepare(format: SingAudioFormat) async throws -> Int64 { 0 }

    func process(_ input: SingAudioBuffer, vocalPercent: Int) throws -> SingAudioBuffer { input }
}

private class PipelineStreamingTestSeparator: SingStreamingSeparator, @unchecked Sendable {
    let backend = "test-streaming"
    let modelRevision = "test-streaming-1"
    private var pending: SingAudioBuffer?

    func prepare(format: SingAudioFormat) async throws -> Int64 { 0 }

    func process(_ input: SingAudioBuffer, vocalPercent: Int) throws -> SingAudioBuffer { input }

    func processStreaming(_ input: SingAudioBuffer, vocalPercent: Int) throws -> [SingAudioBuffer] {
        pending = input
        return []
    }

    func finishStreaming() throws -> [SingAudioBuffer] {
        defer { pending = nil }
        return pending.map { [$0] } ?? []
    }
}

private final class PipelineFailingFlushSeparator: SingStreamingSeparator, @unchecked Sendable {
    let backend = "test-failing-streaming"
    let modelRevision = "test-failing-streaming-1"

    func prepare(format: SingAudioFormat) async throws -> Int64 { 0 }

    func process(_ input: SingAudioBuffer, vocalPercent: Int) throws -> SingAudioBuffer { input }

    func processStreaming(_ input: SingAudioBuffer, vocalPercent: Int) throws -> [SingAudioBuffer] {
        []
    }

    func finishStreaming() throws -> [SingAudioBuffer] {
        throw SingAudioError.unavailable("flush failed")
    }
}

private final class PipelineTestOutput: SingOutputSink, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0
    var onEnqueue: (() -> Void)?
    var onFailure: (@Sendable (String) -> Void)?

    func start(format: SingAudioFormat) throws {}

    func enqueue(_ buffer: SingAudioBuffer) {
        lock.lock()
        count += 1
        let callback = onEnqueue
        lock.unlock()
        callback?()
    }

    func stop() {}
}
