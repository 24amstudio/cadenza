import AVFAudio
import Foundation

/// A model-free fallback for stereo tracks. Center suppression reduces centered
/// vocals while preserving the side channel, but can also affect centered drums
/// and bass. It is intentionally separate from a neural separator backend.
final class StereoCenterSuppressor: SingSeparator, @unchecked Sendable {
    let backend = "stereo-center"
    let modelRevision = "dsp-1"

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
        let left = source[0]
        let right = source[1]
        let renderedLeft = output.floatChannelData![0]
        let renderedRight = output.floatChannelData![1]
        for index in 0..<Int(input.samples.frameLength) {
            let center = (left[index] + right[index]) * 0.5
            let side = (left[index] - right[index]) * 0.5
            renderedLeft[index] = side + center * vocal
            renderedRight[index] = -side + center * vocal
        }
        return SingAudioBuffer(
            format: input.format,
            frameCount: Int(output.frameLength),
            samples: output)
    }
}
