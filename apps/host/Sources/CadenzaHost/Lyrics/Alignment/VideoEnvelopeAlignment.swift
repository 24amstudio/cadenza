import Accelerate
import Foundation

/// Aligns a music video's audio envelope against its studio track using Accelerate SIMD cross-correlation (`vDSP_conv`).
/// Both sides are reduced to 100 Hz mono RMS envelopes so matching compares loudness shape rather than protected PCM.
enum VideoEnvelopeAlignment {
    /// Envelope frames per second: one level value every 10 ms.
    static let framesPerSecond = 100
    static let frameDurationMs: Int64 = 10

    /// The RMS level of consecutive 10 ms windows of mono samples.
    static func envelope(samples: [Float], sampleRate: Double) -> [Float] {
        let window = max(1, Int(sampleRate) / framesPerSecond)
        let frameCount = samples.count / window
        guard frameCount > 0 else { return [] }
        return (0..<frameCount).map { frame in
            let start = frame * window
            var meanSquare: Float = 0
            samples.withUnsafeBufferPointer { buffer in
                vDSP_measqv(buffer.baseAddress! + start, 1, &meanSquare, vDSP_Length(window))
            }
            return meanSquare.squareRoot()
        }
    }

    /// Raw sliding cross-correlation computed with Accelerate `vDSP_conv` (positive kernel stride).
    static func crossCorrelate(signal: [Float], kernel: [Float]) -> [Float] {
        guard !kernel.isEmpty, signal.count >= kernel.count else { return [] }
        let outputCount = signal.count - kernel.count + 1
        var output = [Float](repeating: 0, count: outputCount)
        signal.withUnsafeBufferPointer { signalPtr in
            kernel.withUnsafeBufferPointer { kernelPtr in
                vDSP_conv(
                    signalPtr.baseAddress!, 1,
                    kernelPtr.baseAddress!, 1,
                    &output, 1,
                    vDSP_Length(outputCount),
                    vDSP_Length(kernel.count))
            }
        }
        return output
    }

    /// The lag, in envelope frames, at which `captured` best matches `studio`, and its normalized correlation [-1, 1].
    static func bestLag(studio: [Float], captured: [Float], maximumLag: Int) -> (lag: Int, correlation: Float)? {
        let studioCentered = centered(studio)
        let kernelLength = studioCentered.count
        guard kernelLength > 0, captured.count >= kernelLength, maximumLag >= 0 else { return nil }
        var studioEnergy: Float = 0
        vDSP_dotpr(studioCentered, 1, studioCentered, 1, &studioEnergy, vDSP_Length(kernelLength))
        guard studioEnergy > 0 else { return nil }

        let searchLimit = min(maximumLag, captured.count - kernelLength)
        let searchSlice = Array(captured[0..<(searchLimit + kernelLength)])
        let dots = crossCorrelate(signal: searchSlice, kernel: studioCentered)
        guard !dots.isEmpty else { return nil }

        // Sliding window variance via Double prefix sums avoids per-lag buffer copies.
        var prefixSum = [Double](repeating: 0, count: searchSlice.count + 1)
        var prefixSq = [Double](repeating: 0, count: searchSlice.count + 1)
        for index in 0..<searchSlice.count {
            let value = Double(searchSlice[index])
            prefixSum[index + 1] = prefixSum[index] + value
            prefixSq[index + 1] = prefixSq[index] + value * value
        }

        let invCount = 1.0 / Double(kernelLength)
        let studioNorm = Double(studioEnergy).squareRoot()
        var best: (lag: Int, correlation: Float)?
        for lag in 0...searchLimit {
            let sum = prefixSum[lag + kernelLength] - prefixSum[lag]
            let sq = prefixSq[lag + kernelLength] - prefixSq[lag]
            let variance = max(0, sq - sum * sum * invCount)
            let denominator = studioNorm * variance.squareRoot()
            let correlation = denominator > 0 ? Float(Double(dots[lag]) / denominator) : 0
            if best == nil || correlation > best!.correlation {
                best = (lag, correlation)
            }
        }
        return best
    }

    /// Computes piecewise alignment segments by correlating chunks of `studio` against `captured` in monotonic order.
    /// Chunks that fail `minCorrelation` are omitted so lyrics hide during non-musical story scenes.
    static func piecewiseSegments(
        studio: [Float],
        captured: [Float],
        chunkFrames: Int = 500,
        minCorrelation: Float = 0.55,
        mergeToleranceMs: Int64 = 250
    ) -> [VideoLyricAligner.Segment] {
        guard chunkFrames >= 50, studio.count >= 50, captured.count >= 50 else { return [] }
        var rawSegments: [VideoLyricAligner.Segment] = []
        var studioStart = 0
        var searchStart = 0

        while studioStart < studio.count {
            let studioEnd = min(studio.count, studioStart + chunkFrames)
            let length = studioEnd - studioStart
            guard length >= min(chunkFrames, 200) || rawSegments.isEmpty else { break }
            guard searchStart + length <= captured.count else { break }

            let chunk = Array(studio[studioStart..<studioEnd])
            let window = Array(captured[searchStart..<captured.count])
            let maxLag = window.count - length
            if let match = bestLag(studio: chunk, captured: window, maximumLag: maxLag),
                match.correlation >= minCorrelation
            {
                let videoFrame = searchStart + match.lag
                let offsetMs = Int64(videoFrame - studioStart) * frameDurationMs
                rawSegments.append(
                    VideoLyricAligner.Segment(
                        studioStartMs: Int64(studioStart) * frameDurationMs,
                        studioEndMs: Int64(studioEnd) * frameDurationMs,
                        videoOffsetMs: offsetMs))
                searchStart = videoFrame + length
            }
            studioStart = studioEnd
        }

        return mergeAdjacent(rawSegments, toleranceMs: mergeToleranceMs)
    }

    private static func mergeAdjacent(
        _ segments: [VideoLyricAligner.Segment],
        toleranceMs: Int64
    ) -> [VideoLyricAligner.Segment] {
        var merged: [VideoLyricAligner.Segment] = []
        for segment in segments {
            if var last = merged.last,
                last.studioEndMs == segment.studioStartMs,
                abs(last.videoOffsetMs - segment.videoOffsetMs) <= toleranceMs
            {
                last.studioEndMs = segment.studioEndMs
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
        }
        return merged
    }

    private static func centered(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return [] }
        var mean: Float = 0
        vDSP_meanv(values, 1, &mean, vDSP_Length(values.count))
        var negatedMean = -mean
        var output = [Float](repeating: 0, count: values.count)
        vDSP_vsadd(values, 1, &negatedMean, &output, 1, vDSP_Length(values.count))
        return output
    }
}
