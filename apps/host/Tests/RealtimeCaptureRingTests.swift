import AVFAudio
import Darwin
import XCTest

@testable import CadenzaHost

/// The capture ring sits between the Core Audio IOProc and the consumer. These tests cover its ordering and its
/// realtime contract: the producer path must not allocate.
final class RealtimeCaptureRingTests: XCTestCase {
    private typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

    func testPlanarBlocksKeepTheirOrderAndChannels() throws {
        let ring = try XCTUnwrap(RealtimeCaptureRing(channelCount: 2, frameCapacity: 8, slotCount: 2))
        let left = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        defer {
            left.deallocate()
            right.deallocate()
        }
        for frame in 0..<8 {
            left[frame] = Float(frame)
            right[frame] = Float(frame) + 100
        }
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8 * 4, mData: left)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8 * 4, mData: right)

        XCTAssertTrue(ring.write(list, frameCount: 8))
        let read = try XCTUnwrap(ring.read())
        XCTAssertEqual(read.frameCount, 8)
        for frame in 0..<8 {
            XCTAssertEqual(ring.samples(for: read, channel: 0)[frame], Float(frame))
            XCTAssertEqual(ring.samples(for: read, channel: 1)[frame], Float(frame) + 100)
        }
        ring.release(read)
        XCTAssertNil(ring.read())
    }

    func testAFullRingDropsTheNewestBlock() throws {
        let ring = try XCTUnwrap(RealtimeCaptureRing(channelCount: 1, frameCapacity: 4, slotCount: 2))
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        defer { samples.deallocate() }
        samples.initialize(repeating: 0.5, count: 4)
        let list = AudioBufferList.allocate(maximumBuffers: 1)
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 4 * 4, mData: samples)

        XCTAssertTrue(ring.write(list, frameCount: 4))
        XCTAssertTrue(ring.write(list, frameCount: 4))
        XCTAssertFalse(ring.write(list, frameCount: 4), "A full ring must drop instead of growing.")
    }

    func testTheRealtimeProducerDoesNotAllocate() throws {
        // The probe counts every malloc on this thread, including the ones a debug Swift build makes for its own
        // bookkeeping inside any loop. Only an optimized build measures the real producer path, so the default
        // `swift test` run skips it and the release run proves it.
        try XCTSkipUnless(
            !_isDebugAssertConfiguration(),
            "Run `swift test -c release --filter RealtimeCaptureRingTests` to measure allocations.")

        let ring = try XCTUnwrap(RealtimeCaptureRing(channelCount: 2, frameCapacity: 512, slotCount: 8))
        let left = UnsafeMutablePointer<Float>.allocate(capacity: 512)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: 512)
        defer {
            left.deallocate()
            right.deallocate()
        }
        left.initialize(repeating: 0.25, count: 512)
        right.initialize(repeating: 0.5, count: 512)
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 512 * 4, mData: left)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 512 * 4, mData: right)

        // Warm the ring and the wake signal before the probe, so lazy framework setup is not counted.
        for _ in 0..<4 {
            XCTAssertTrue(ring.write(list, frameCount: 512))
            while let read = ring.read() { ring.release(read) }
        }

        allocationProbeCount = 0
        allocationProbeThread = pthread_self()
        let installed = installMallocLogger { type, _, _, _, _, _ in
            guard type & 2 != 0, let thread = allocationProbeThread,
                pthread_equal(pthread_self(), thread) != 0
            else { return }
            allocationProbeCount += 1
        }
        if installed {
            for _ in 0..<64 {
                _ = ring.write(list, frameCount: 512)
                while let read = ring.read() { ring.release(read) }
            }
        }
        installMallocLogger(nil)
        allocationProbeThread = nil
        XCTAssertTrue(installed, "The allocation probe needs libmalloc's malloc_logger.")
        XCTAssertEqual(allocationProbeCount, 0, "The realtime producer path allocated memory.")
    }

    /// Installs libmalloc's allocation hook. It is a process-wide function pointer, so tests use it one at a time.
    @discardableResult
    private func installMallocLogger(_ logger: MallocLogger?) -> Bool {
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "malloc_logger") else { return false }
        symbol.assumingMemoryBound(to: MallocLogger?.self).pointee = logger
        return true
    }
}

private nonisolated(unsafe) var allocationProbeCount = 0
private nonisolated(unsafe) var allocationProbeThread: pthread_t?
