import AVFAudio
import Foundation

/// A model-free fallback for stereo tracks. Center suppression removes centered
/// vocals, but mixes also keep bass and kick centered, so removing the whole
/// center also removes the low end and leaves the output mono-silent. The center
/// below `bassCutoffHz` therefore stays at every vocal mix; only mid and high
/// center content follows the vocal setting. It is intentionally separate from a
/// neural separator backend.
final class StereoCenterSuppressor: SingSeparator, @unchecked Sendable {
    let backend = "stereo-center"
    let modelRevision = "dsp-2"
    private static let bassCutoffHz = 120.0
    // process runs only on the serial Sing DSP queue, so this filter state is never shared.
    private var bassFilter: LowPassBiquad?

    func prepare(format: SingAudioFormat) async throws -> Int64 {
        guard format.channelCount == 2 else {
            throw SingAudioError.unavailable("The stereo fallback requires a two-channel Music output.")
        }
        return 20
    }

    func process(_ input: SingAudioBuffer, vocalPercent: Int) throws -> SingAudioBuffer {
        guard input.format.channelCount == 2,
            let source = input.samples.floatChannelData,
            let output = AVAudioPCMBuffer(
                pcmFormat: input.samples.format,
                frameCapacity: input.samples.frameLength)
        else {
            throw SingAudioError.unavailable("The stereo fallback received an unsupported audio buffer.")
        }
        guard (0...100).contains(vocalPercent) else { throw SingAudioError.invalidMix }
        output.frameLength = input.samples.frameLength
        let vocal = Float(vocalPercent) / 100
        let bass = currentBassFilter(for: input.format.sampleRate)
        let left = source[0]
        let right = source[1]
        let renderedLeft = output.floatChannelData![0]
        let renderedRight = output.floatChannelData![1]
        for index in 0..<Int(input.samples.frameLength) {
            let mid = (left[index] + right[index]) * 0.5
            let side = (left[index] - right[index]) * 0.5
            let low = bass.process(mid)
            let center = low + (mid - low) * vocal
            renderedLeft[index] = side + center
            renderedRight[index] = -side + center
        }
        return SingAudioBuffer(
            format: input.format,
            frameCount: Int(output.frameLength),
            samples: output)
    }

    private func currentBassFilter(for sampleRate: Double) -> LowPassBiquad {
        if let bassFilter, bassFilter.sampleRate == sampleRate { return bassFilter }
        let filter = LowPassBiquad(cutoffHz: Self.bassCutoffHz, sampleRate: sampleRate)
        bassFilter = filter
        return filter
    }
}

/// Second-order Butterworth low-pass. Its state carries across buffers, so one
/// instance must only be used from one stream's DSP queue.
private final class LowPassBiquad {
    let sampleRate: Double
    private let b0: Double
    private let b1: Double
    private let b2: Double
    private let a1: Double
    private let a2: Double
    private var x1 = 0.0
    private var x2 = 0.0
    private var y1 = 0.0
    private var y2 = 0.0

    init(cutoffHz: Double, sampleRate: Double) {
        let k = tan(Double.pi * cutoffHz / sampleRate)
        let root2 = 2.0.squareRoot()
        let norm = 1 / (1 + root2 * k + k * k)
        self.sampleRate = sampleRate
        b0 = k * k * norm
        b1 = 2 * b0
        b2 = b0
        a1 = 2 * (k * k - 1) * norm
        a2 = (1 - root2 * k + k * k) * norm
    }

    func process(_ sample: Float) -> Float {
        let x = Double(sample)
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return Float(y)
    }
}
