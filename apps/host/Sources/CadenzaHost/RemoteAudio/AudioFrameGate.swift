import Foundation

/// Decides whether one audio frame may enter the Remote socket. The Host drops a frame rather than let TCP queue it,
/// because a queued frame arrives after its playout instant and drags the whole stream behind it.
struct AudioFrameGate {
    enum Decision: Equatable, Sendable {
        case send
        /// Two frames are already unacknowledged, which is the 21.33 ms cap.
        case dropInFlightFull
        /// The frame could not reach the Remote before its playout instant.
        case dropTooLate
    }

    static let maximumInFlight = 2
    static let minimumTransportLeadUs: UInt64 = 4_000
    static let degradedDropsPerSecond = 25
    static let degradedAfterUs: UInt64 = 3_000_000
    static let statsWindowUs: UInt64 = 60_000_000

    /// Drop times within the last 60 seconds. Used for `droppedStaleFrames60s` and the one-second rate.
    private var dropTimesUs: [UInt64] = []
    private var overRateSinceUs: UInt64?

    /// Applies both invariants. A frame that is dropped is recorded in the 60-second counter.
    mutating func admit(nowUs: UInt64, targetPlayoutUs: UInt64, inFlight: Int) -> Decision {
        let decision: Decision
        if inFlight >= Self.maximumInFlight {
            decision = .dropInFlightFull
        } else if nowUs &+ Self.minimumTransportLeadUs >= targetPlayoutUs {
            decision = .dropTooLate
        } else {
            decision = .send
        }
        if decision != .send {
            dropTimesUs.append(nowUs)
        }
        pruneDrops(nowUs: nowUs)
        updateRate(nowUs: nowUs)
        return decision
    }

    mutating func droppedStaleFrames60s(nowUs: UInt64) -> Int {
        pruneDrops(nowUs: nowUs)
        return dropTimesUs.count
    }

    /// True once more than 25 frames a second have been dropped for more than 3 seconds in a row. The Host then tears
    /// the stream down and restores Music's normal local output.
    mutating func isDegraded(nowUs: UInt64) -> Bool {
        pruneDrops(nowUs: nowUs)
        updateRate(nowUs: nowUs)
        guard let since = overRateSinceUs else { return false }
        return nowUs &- since >= Self.degradedAfterUs
    }

    private mutating func pruneDrops(nowUs: UInt64) {
        let cutoff = nowUs > Self.statsWindowUs ? nowUs - Self.statsWindowUs : 0
        dropTimesUs.removeAll { $0 < cutoff }
    }

    private mutating func updateRate(nowUs: UInt64) {
        let oneSecondAgo = nowUs > 1_000_000 ? nowUs - 1_000_000 : 0
        let recent = dropTimesUs.count(where: { $0 >= oneSecondAgo })
        if recent > Self.degradedDropsPerSecond {
            overRateSinceUs = overRateSinceUs ?? nowUs
        } else {
            overRateSinceUs = nil
        }
    }
}
