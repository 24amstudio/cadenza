import AVFAudio
import Foundation

/// Reuses a small number of capture buffers so the Core Audio callback does
/// not allocate for every device block. A full pool drops the block.
final class SingAudioBufferPool: @unchecked Sendable {
    private let format: AVAudioFormat
    private let capacity: Int
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer?]

    init(format: AVAudioFormat, capacity: Int, count: Int = 4) {
        self.format = format
        self.capacity = capacity
        self.buffers = (0..<count).map { _ in
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity))
        }
    }

    func acquire(frameCount: Int) -> (buffer: AVAudioPCMBuffer, lease: SingAudioBufferLease)? {
        guard (1...capacity).contains(frameCount) else { return nil }
        lock.lock()
        guard let index = buffers.firstIndex(where: { $0 != nil }), let buffer = buffers[index] else {
            lock.unlock()
            return nil
        }
        buffers[index] = nil
        lock.unlock()
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let lease = SingAudioBufferLease { [weak self, weak buffer] in
            guard let self, let buffer else { return }
            self.returnBuffer(buffer, at: index)
        }
        return (buffer, lease)
    }

    private func returnBuffer(_ buffer: AVAudioPCMBuffer, at index: Int) {
        lock.lock()
        if buffers.indices.contains(index), buffers[index] == nil {
            buffers[index] = buffer
        }
        lock.unlock()
    }
}
