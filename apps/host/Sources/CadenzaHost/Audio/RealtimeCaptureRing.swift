import AVFAudio
import Foundation
import Synchronization

/// A preallocated single-producer, single-consumer ring between the Core Audio IOProc and a consumer queue.
///
/// The producer runs on the realtime thread. It only copies planar Float samples into a free slot and publishes the
/// new index, so it never allocates, locks, waits, or logs. The consumer drains slots on its own queue, turns them
/// into pooled buffers, and calls the capture receiver. A full ring drops the newest block, which keeps the realtime
/// path bounded without growing memory.
final class RealtimeCaptureRing: @unchecked Sendable {
    /// One published block. The slot stays reserved until `release` returns it to the producer. `hostTime` is the device
    /// clock time of its first sample, in mach absolute time.
    struct Read {
        let slot: Int
        let frameCount: Int
        let channelCount: Int
        let hostTime: UInt64
    }

    let channelCount: Int
    let frameCapacity: Int
    let slotCount: Int
    private let samples: UnsafeMutablePointer<Float>
    private let frameCounts: UnsafeMutablePointer<Int>
    private let hostTimes: UnsafeMutablePointer<UInt64>
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)
    private let wake = DispatchSemaphore(value: 0)
    private let stopped = Atomic<Bool>(false)

    /// Nil when the requested layout is empty.
    init?(channelCount: Int, frameCapacity: Int, slotCount: Int = 8) {
        guard channelCount > 0, frameCapacity > 0, slotCount > 1 else { return nil }
        self.channelCount = channelCount
        self.frameCapacity = frameCapacity
        self.slotCount = slotCount
        samples = UnsafeMutablePointer<Float>.allocate(capacity: channelCount * frameCapacity * slotCount)
        frameCounts = UnsafeMutablePointer<Int>.allocate(capacity: slotCount)
        hostTimes = UnsafeMutablePointer<UInt64>.allocate(capacity: slotCount)
        samples.initialize(repeating: 0, count: channelCount * frameCapacity * slotCount)
        frameCounts.initialize(repeating: 0, count: slotCount)
        hostTimes.initialize(repeating: 0, count: slotCount)
    }

    deinit {
        samples.deinitialize(count: channelCount * frameCapacity * slotCount)
        samples.deallocate()
        frameCounts.deinitialize(count: slotCount)
        frameCounts.deallocate()
        hostTimes.deinitialize(count: slotCount)
        hostTimes.deallocate()
    }

    /// True after `stop`. The consumer exits on its next pass.
    var isStopped: Bool { stopped.load(ordering: .acquiring) }

    /// Waits up to `timeout` for a published block. The consumer only calls this; the producer never waits.
    func waitForFrames(timeout: DispatchTime) -> Bool {
        wake.wait(timeout: timeout) == .success
    }

    /// Copies one device block straight from the IOProc pointer, so the realtime path never reads outside state.
    @inline(__always)
    func write(_ inputData: UnsafePointer<AudioBufferList>, hostTime: UInt64 = 0) -> Bool {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard let first = buffers.first, first.mData != nil else { return false }
        let frameCount =
            buffers.count >= 2
            ? Int(first.mDataByteSize) / MemoryLayout<Float>.size
            : Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channelCount)
        return write(buffers, frameCount: frameCount, hostTime: hostTime)
    }

    /// Copies one device block. Called only from the realtime IOProc, so it must stay allocation-free.
    ///
    /// `buffers` is planar when it holds one buffer per channel and interleaved when it holds a single buffer.
    @inline(__always)
    func write(_ buffers: UnsafeMutableAudioBufferListPointer, frameCount: Int, hostTime: UInt64 = 0) -> Bool {
        guard frameCount > 0, frameCount <= frameCapacity, buffers.count > 0 else { return false }
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        guard write - read < slotCount else { return false }
        let slot = write % slotCount
        let base = samples + slot * channelCount * frameCapacity
        if buffers.count >= 2 {
            let planar = min(buffers.count, channelCount)
            for channel in 0..<planar {
                let destination = base + channel * frameCapacity
                guard let data = buffers[channel].mData else {
                    memset(destination, 0, frameCount * MemoryLayout<Float>.size)
                    continue
                }
                memcpy(destination, data, frameCount * MemoryLayout<Float>.size)
            }
            for channel in planar..<channelCount {
                memset(base + channel * frameCapacity, 0, frameCount * MemoryLayout<Float>.size)
            }
        } else {
            guard let data = buffers[0].mData else { return false }
            let interleaved = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                for channel in 0..<channelCount {
                    base[channel * frameCapacity + frame] = interleaved[frame * channelCount + channel]
                }
            }
        }
        frameCounts[slot] = frameCount
        hostTimes[slot] = hostTime
        writeIndex.store(write + 1, ordering: .releasing)
        wake.signal()
        return true
    }

    /// The oldest published block, if one is waiting. Only the consumer calls this.
    func read() -> Read? {
        let read = readIndex.load(ordering: .relaxed)
        guard read < writeIndex.load(ordering: .acquiring) else { return nil }
        let slot = read % slotCount
        return Read(slot: slot, frameCount: frameCounts[slot], channelCount: channelCount, hostTime: hostTimes[slot])
    }

    /// Returns a block to the producer. Only the consumer calls this.
    func release(_ read: Read) {
        readIndex.store(readIndex.load(ordering: .relaxed) + 1, ordering: .releasing)
    }

    /// The samples of one channel in a published block, as the consumer copies them into its own buffer.
    func samples(for read: Read, channel: Int) -> UnsafePointer<Float> {
        UnsafePointer(samples + (read.slot * channelCount + channel) * frameCapacity)
    }

    /// Wakes the consumer so it can exit.
    func stop() {
        stopped.store(true, ordering: .releasing)
        wake.signal()
    }
}
