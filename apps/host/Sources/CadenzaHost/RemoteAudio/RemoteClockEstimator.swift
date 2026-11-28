import Foundation

/// Estimates the Remote clock's offset from the Host clock from ping and pong timestamps. The Host sends each ping at
/// `t1`, the Remote receives it at `t2` and answers at `t3`, and the Host receives the pong at `t4`. The sample with
/// the smallest round trip is the most reliable, so Wi-Fi jitter spikes do not move the estimate. Drift is the rate of
/// change of that offset, measured over at least a minute.
struct RemoteClockEstimator {
    struct Sample: Equatable, Sendable {
        /// The Host time at which the sample was taken.
        let hostUs: UInt64
        /// Remote clock minus Host clock, in microseconds.
        let offsetUs: Int64
        let rttUs: Int64
        let processingUs: Int64

        var totalUs: Int64 { rttUs + processingUs }
    }

    /// Thirty pings at 2 seconds is one minute of history.
    static let windowSize = 30
    static let driftIntervalUs: UInt64 = 60_000_000

    private var samples: [Sample] = []
    private var driftAnchor: Sample?
    private(set) var driftPpm = 0.0

    /// Adds one exchange. Returns nil when the timestamps are impossible, such as a round trip that is negative.
    @discardableResult
    mutating func add(t1: UInt64, t2: UInt64, t3: UInt64, t4: UInt64) -> Sample? {
        let processing = Int64(bitPattern: t3) &- Int64(bitPattern: t2)
        let rtt = (Int64(bitPattern: t4) &- Int64(bitPattern: t1)) &- processing
        guard rtt >= 0, processing >= 0, t4 >= t1 else { return nil }
        let offset =
            ((Int64(bitPattern: t2) &- Int64(bitPattern: t1)) &+ (Int64(bitPattern: t3) &- Int64(bitPattern: t4))) / 2
        let sample = Sample(hostUs: t4, offsetUs: offset, rttUs: rtt, processingUs: processing)
        samples.append(sample)
        if samples.count > Self.windowSize {
            samples.removeFirst()
        }
        updateDrift()
        return sample
    }

    /// The sample with the smallest round trip in the window.
    var best: Sample? {
        samples.min { $0.rttUs < $1.rttUs }
    }

    var latest: Sample? {
        samples.last
    }

    /// The spread between the largest and smallest round trip in the window. Wi-Fi jitter widens it, so the jitter
    /// cushion grows with it. Nil until a sample exists.
    var rttSpreadUs: Int64? {
        guard let high = samples.map(\.rttUs).max(), let low = samples.map(\.rttUs).min() else { return nil }
        return high - low
    }

    /// Remote minus Host at a Host time, extrapolated from the best sample with the measured drift.
    func offsetUs(atHostUs hostUs: UInt64) -> Int64? {
        guard let best else { return nil }
        let elapsed = Double(Int64(bitPattern: hostUs) &- Int64(bitPattern: best.hostUs))
        return best.offsetUs + Int64((elapsed * driftPpm / 1_000_000).rounded())
    }

    private mutating func updateDrift() {
        guard let best else { return }
        guard let anchor = driftAnchor else {
            driftAnchor = best
            return
        }
        // The best sample can be older than the anchor after the window slides, so only a later sample measures drift.
        guard best.hostUs > anchor.hostUs else { return }
        let elapsed = best.hostUs - anchor.hostUs
        guard elapsed >= Self.driftIntervalUs else { return }
        let offsetChange = Double(best.offsetUs - anchor.offsetUs)
        driftPpm = offsetChange / Double(elapsed) * 1_000_000
        driftAnchor = best
    }
}
