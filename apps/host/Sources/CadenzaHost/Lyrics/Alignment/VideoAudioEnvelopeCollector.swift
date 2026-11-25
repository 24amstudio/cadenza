import Accelerate
import Foundation

/// Accumulates a bounded 100 Hz mono RMS envelope from Music's real-time audio buffer callbacks without allocations per sample.
final class VideoAudioEnvelopeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [Float] = []
    private var sampleAccumulator: Double = 0
    private var sampleCount: Int = 0
    private let maxFrames: Int

    init(maxSeconds: Int = 600) {
        maxFrames = maxSeconds * VideoEnvelopeAlignment.framesPerSecond
    }

    func append(buffer: SingAudioBuffer) {
        let count = buffer.frameCount
        guard count > 0, let channels = buffer.samples.floatChannelData else { return }
        let channelCount = max(1, buffer.format.channelCount)
        let windowSize = max(1, Int(buffer.format.sampleRate) / VideoEnvelopeAlignment.framesPerSecond)

        lock.lock()
        defer { lock.unlock() }
        for index in 0..<count {
            var mono: Float = 0
            for ch in 0..<channelCount {
                mono += channels[ch][index]
            }
            mono /= Float(channelCount)
            sampleAccumulator += Double(mono * mono)
            sampleCount += 1
            if sampleCount >= windowSize {
                let rms = Float((sampleAccumulator / Double(sampleCount)).squareRoot())
                if frames.count >= maxFrames { frames.removeFirst() }
                frames.append(rms)
                sampleAccumulator = 0
                sampleCount = 0
            }
        }
    }

    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        frames.removeAll(keepingCapacity: true)
        sampleAccumulator = 0
        sampleCount = 0
    }
}
