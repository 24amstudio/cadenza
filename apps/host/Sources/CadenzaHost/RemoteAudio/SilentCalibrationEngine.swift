import Accelerate
import Foundation

/// Aligns the sub and the mains without a test tone. Stage 1 uses the electronic latency from the handshake and
/// CoreAudio, so it runs on connect. Stage 2 estimates the room's acoustic delay passively, from the Mac's microphone
/// while music plays. Each reference is cross-correlated with the microphone to find its arrival time.
enum SilentCalibrationEngine {
    /// The search covers 100 ms on each side of zero. The microphone and the Host's references start on different
    /// clocks, and that common offset moves both peaks by the same amount. The acoustic delta cancels it out.
    static let maximumLagMs = 100.0

    /// Stage 1: the Remote's `baseLatencyMs + outputLatencyMs` minus the Host's electronic latency, in milliseconds.
    static func electronicDeltaMs(
        remoteBaseLatencyMs: Double, remoteOutputLatencyMs: Double, hostLatencyFrames: Int, sampleRate: Double
    ) -> Double {
        (remoteBaseLatencyMs + remoteOutputLatencyMs) - Double(hostLatencyFrames) / sampleRate * 1_000
    }

    /// Stage 2: the mains arrival delay minus the sub arrival delay, in milliseconds. A positive value means the mains
    /// reach the microphone later than the sub, so the sub is delayed by the difference.
    static func acousticDeltaMs(
        mic: [Float], mainsReference: [Float], subReference: [Float], sampleRate: Double
    ) -> Double? {
        guard
            let mains = peakDelayMs(signal: mic, reference: mainsReference, sampleRate: sampleRate),
            let sub = peakDelayMs(signal: mic, reference: subReference, sampleRate: sampleRate)
        else { return nil }
        return mains - sub
    }

    /// How many milliseconds `signal` lags `reference`, from the peak of their cross-correlation. Negative values mean
    /// the signal leads. The peak is refined with a parabolic fit, so the result is finer than one sample. Returns nil
    /// when the window is too short to hold the largest lag on both sides.
    static func peakDelayMs(signal: [Float], reference: [Float], sampleRate: Double) -> Double? {
        let count = min(signal.count, reference.count)
        let span = Int(maximumLagMs / 1_000 * sampleRate)
        guard count > span + 1 else { return nil }
        // scores[index] holds the correlation at lag index - span.
        var scores = [Float](repeating: 0, count: 2 * span + 1)
        signal.withUnsafeBufferPointer { s in
            reference.withUnsafeBufferPointer { r in
                for index in 0...(2 * span) {
                    let lag = index - span
                    let length = vDSP_Length(count - abs(lag))
                    var dot: Float = 0
                    if lag >= 0 {
                        // Σ signal[k + lag] × reference[k]: the signal lags the reference by `lag`.
                        vDSP_dotpr(s.baseAddress! + lag, 1, r.baseAddress!, 1, &dot, length)
                    } else {
                        // Σ signal[k] × reference[k + |lag|]: the signal leads the reference.
                        vDSP_dotpr(s.baseAddress!, 1, r.baseAddress! + abs(lag), 1, &dot, length)
                    }
                    scores[index] = dot
                }
            }
        }
        guard let peak = scores.indices.max(by: { scores[$0] < scores[$1] }) else { return nil }
        var refinement = 0.0
        if peak > 0 && peak < scores.count - 1 {
            let before = Double(scores[peak - 1])
            let after = Double(scores[peak + 1])
            let center = Double(scores[peak])
            let curvature = before - 2 * center + after
            if curvature < 0 {
                refinement = 0.5 * (before - after) / curvature
            }
        }
        return (Double(peak - span) + refinement) / sampleRate * 1_000
    }
}
