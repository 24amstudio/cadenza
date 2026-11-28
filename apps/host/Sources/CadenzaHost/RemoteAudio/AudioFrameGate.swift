import Foundation

/// Decides whether one audio frame may enter the Remote socket. The Host drops a frame rather than let TCP queue it,
/// because a queued frame arrives after its playout instant and drags the whole stream behind it.
struct AudioFrameGate {
    enum Decision: Equatable, Sendable {
        case send
        case dropInFlightFull
        /// The frame could not reach the Remote before its playout instant.
        case dropTooLate
    }

    static let maximumInFlight = 2
    static let minimumTransportLeadUs: UInt64 = 4_000
    static let degradedDropsPerSecond = 25
    static let degradedAfterUs: UInt64 = 3_000_000
    static let statsWindowUs: UInt64 = 60_000_000

    private struct Drop: Equatable {
        let atUs: UInt64
        let decision: Decision
    }

    private var drops: [Drop] = []
    private var firstLive = 0
    private var overRateSinceUs: UInt64?

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
            drops.append(Drop(atUs: nowUs, decision: decision))
        }
        pruneDrops(nowUs: nowUs)
        updateRate(nowUs: nowUs)
        return decision
    }

    mutating func droppedStaleFrames60s(nowUs: UInt64) -> Int {
        pruneDrops(nowUs: nowUs)
        return drops.count - firstLive
    }

    mutating func dropped(_ decision: Decision, nowUs: UInt64) -> Int {
        pruneDrops(nowUs: nowUs)
        return drops[firstLive...].count(where: { $0.decision == decision })
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
        while firstLive < drops.count, drops[firstLive].atUs < cutoff {
            firstLive += 1
        }
        if firstLive > 0, firstLive * 2 >= drops.count {
            drops.removeFirst(firstLive)
            firstLive = 0
        }
    }

    private mutating func updateRate(nowUs: UInt64) {
        let oneSecondAgo = nowUs > 1_000_000 ? nowUs - 1_000_000 : 0
        let recent = drops[firstLive...].count(where: { $0.atUs >= oneSecondAgo })
        if recent > Self.degradedDropsPerSecond {
            overRateSinceUs = overRateSinceUs ?? nowUs
        } else {
            overRateSinceUs = nil
        }
    }
}
