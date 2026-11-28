import Foundation

final class RemoteAudioFrameWriter: @unchecked Sendable {
    typealias Write = @Sendable (Data, @escaping @Sendable () -> Void) -> Void

    struct Statistics: Equatable, Sendable {
        let droppedInFlight: Int
        let droppedLate: Int

        var dropped: Int { droppedInFlight + droppedLate }
    }

    private let lock = NSLock()
    private let write: Write
    private let now: @Sendable () -> UInt64
    private let onDegraded: @Sendable () -> Void
    private var gate = AudioFrameGate()
    private var inFlight = 0
    private var closed = false
    private var reportedDegraded = false
    private var totalDropped = 0

    init(
        write: @escaping Write,
        now: @escaping @Sendable () -> UInt64 = RemoteAudioClock.nowUs,
        onDegraded: @escaping @Sendable () -> Void
    ) {
        self.write = write
        self.now = now
        self.onDegraded = onDegraded
    }

    func send(_ frame: RemoteAudioWire.AudioFrame) {
        let nowUs = now()
        let admitted = lock.withLock { () -> (send: Bool, degraded: Bool) in
            guard !closed else { return (false, false) }
            let decision = gate.admit(nowUs: nowUs, targetPlayoutUs: frame.targetPlayoutHostUs, inFlight: inFlight)
            if decision == .send {
                inFlight += 1
            } else {
                totalDropped += 1
            }
            return (decision == .send, tripDegradedLocked(nowUs))
        }
        if admitted.degraded { onDegraded() }
        guard admitted.send else { return }
        guard let payload = RemoteAudioWire.encode(frame) else {
            lock.withLock { inFlight -= 1 }
            return
        }
        write(payload) { [self] in
            lock.withLock { inFlight -= 1 }
        }
    }

    func sendControl(_ payload: Data) {
        guard lock.withLock({ !closed }) else { return }
        write(payload) {}
    }

    func statistics() -> Statistics {
        let nowUs = now()
        return lock.withLock {
            Statistics(
                droppedInFlight: gate.dropped(.dropInFlightFull, nowUs: nowUs),
                droppedLate: gate.dropped(.dropTooLate, nowUs: nowUs))
        }
    }

    func totalDroppedFrames() -> Int {
        lock.withLock { totalDropped }
    }

    func checkDegraded() {
        let nowUs = now()
        let tripped = lock.withLock { tripDegradedLocked(nowUs) }
        if tripped { onDegraded() }
    }

    func close() {
        lock.withLock { closed = true }
    }

    private func tripDegradedLocked(_ nowUs: UInt64) -> Bool {
        guard !reportedDegraded, gate.isDegraded(nowUs: nowUs) else { return false }
        reportedDegraded = true
        return true
    }
}
