import Accelerate
import Foundation

/// Finds how far a music video's audio runs behind its studio track, from the audio Music plays. Both sides are reduced to
/// a level envelope, so the match ignores timbre and only needs the loudness shape of the two signals to agree. The
/// studio side is a public preview, and the captured side is the output Music plays through the Host's own tap, so no
/// protected stream is read.
enum VideoEnvelopeAlignment {
    /// Envelope frames per second: one level value every 10 ms.
    static let framesPerSecond = 100

    /// The RMS level of consecutive 10 ms windows of mono samples.
    static func envelope(samples: [Float], sampleRate: Double) -> [Float] {
        let window = max(1, Int(sampleRate) / framesPerSecond)
        let frameCount = samples.count / window
        return (0..<frameCount).map { frame in
            let start = frame * window
            var meanSquare: Float = 0
            samples.withUnsafeBufferPointer { buffer in
                vDSP_measqv(buffer.baseAddress! + start, 1, &meanSquare, vDSP_Length(window))
            }
            return meanSquare.squareRoot()
        }
    }

    /// The lag, in envelope frames, at which the captured envelope best matches the studio envelope, and that match's
    /// normalized correlation from -1 to 1. A lag means the captured audio starts that many frames after the studio track.
    static func bestLag(studio: [Float], captured: [Float], maximumLag: Int) -> (lag: Int, correlation: Float)? {
        let studioCentered = centered(studio)
        guard !studioCentered.isEmpty, captured.count >= studioCentered.count else { return nil }
        var best: (lag: Int, correlation: Float)?
        for lag in 0...min(maximumLag, captured.count - studioCentered.count) {
            let window = Array(captured[lag..<(lag + studioCentered.count)])
            let correlation = normalizedCorrelation(studioCentered, centered(window))
            if best == nil || correlation > best!.correlation {
                best = (lag, correlation)
            }
        }
        return best
    }

    private static func centered(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return [] }
        var mean: Float = 0
        vDSP_meanv(values, 1, &mean, vDSP_Length(values.count))
        return values.map { $0 - mean }
    }

    private static func normalizedCorrelation(_ first: [Float], _ second: [Float]) -> Float {
        var dot: Float = 0
        var firstEnergy: Float = 0
        var secondEnergy: Float = 0
        vDSP_dotpr(first, 1, second, 1, &dot, vDSP_Length(first.count))
        vDSP_dotpr(first, 1, first, 1, &firstEnergy, vDSP_Length(first.count))
        vDSP_dotpr(second, 1, second, 1, &secondEnergy, vDSP_Length(second.count))
        let denominator = (firstEnergy * secondEnergy).squareRoot()
        return denominator > 0 ? dot / denominator : 0
    }
}
