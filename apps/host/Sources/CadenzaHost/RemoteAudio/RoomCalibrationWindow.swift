import Foundation

/// Collects the two seconds of microphone audio and the matching sub and mains references that stage 2 correlates. The
/// references are the Host's own blocks, and the microphone is its input. Both are called from capture threads, so the
/// window locks its state.
final class RoomCalibrationWindow: @unchecked Sendable {
    static let seconds = 2.0

    private let frames: Int
    private let lock = NSLock()
    /// Called once, from whichever thread completes the window.
    private let onComplete: @Sendable () -> Void
    private var notified = false
    private var mic: [Float] = []
    private var mains: [Float] = []
    private var sub: [Float] = []

    init(sampleRate: Double, onComplete: @escaping @Sendable () -> Void) {
        frames = Int(sampleRate * Self.seconds)
        self.onComplete = onComplete
    }

    func appendMic(_ samples: [Float]) {
        lock.withLock { Self.fill(&mic, with: samples, to: frames) }
        notifyIfComplete()
    }

    func appendReferences(mains newMains: [Float], sub newSub: [Float]) {
        lock.withLock {
            Self.fill(&mains, with: newMains, to: frames)
            Self.fill(&sub, with: newSub, to: frames)
        }
        notifyIfComplete()
    }

    private func notifyIfComplete() {
        let complete = lock.withLock { () -> Bool in
            guard !notified, mic.count == frames, mains.count == frames, sub.count == frames else { return false }
            notified = true
            return true
        }
        if complete { onComplete() }
    }

    /// The three streams, each exactly two seconds long, once every stream has reached that length.
    func completeWindow() -> (mic: [Float], mains: [Float], sub: [Float])? {
        lock.withLock {
            guard mic.count == frames, mains.count == frames, sub.count == frames else { return nil }
            return (mic, mains, sub)
        }
    }

    private static func fill(_ stream: inout [Float], with samples: [Float], to limit: Int) {
        guard stream.count < limit else { return }
        stream.append(contentsOf: samples.prefix(limit - stream.count))
    }
}
