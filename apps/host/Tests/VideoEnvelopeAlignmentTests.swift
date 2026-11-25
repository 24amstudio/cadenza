import Foundation
import Testing

@testable import CadenzaHost

struct VideoEnvelopeAlignmentTests {
    // A level pattern with quiet gaps, like a song with breaks, built from two tones with a slow swell.
    private func music(seconds: Int, sampleRate: Double) -> [Float] {
        (0..<(seconds * Int(sampleRate))).map { index in
            let time = Double(index) / sampleRate
            let swell = 0.5 + 0.5 * sin(2 * .pi * 0.3 * time)
            let gap = sin(2 * .pi * 0.11 * time) > -0.4 ? 1.0 : 0.0
            return Float(0.6 * swell * gap * sin(2 * .pi * 220 * time) + 0.2 * swell * sin(2 * .pi * 330 * time))
        }
    }

    @Test func aVideoThatStartsLaterThanItsStudioTrackIsFoundAtThatLag() throws {
        let rate = 16_000.0
        let studioSamples = music(seconds: 30, sampleRate: rate)
        // The captured output begins 2.5 seconds before the studio track's preview would, so the studio track starts 250
        // frames in: the lag is the offset of the studio track inside the captured audio.
        let captured = Array(repeating: Float(0), count: Int(2.5 * rate)) + studioSamples
        let studio = VideoEnvelopeAlignment.envelope(samples: studioSamples, sampleRate: rate)
        let heard = VideoEnvelopeAlignment.envelope(samples: captured, sampleRate: rate)

        let match = try #require(VideoEnvelopeAlignment.bestLag(studio: studio, captured: heard, maximumLag: 600))

        #expect(match.lag == 250)
        #expect(match.correlation > 0.95)
    }

    @Test func unrelatedAudioDoesNotMatchTheStudioTrack() throws {
        let rate = 16_000.0
        let studio = VideoEnvelopeAlignment.envelope(samples: music(seconds: 20, sampleRate: rate), sampleRate: rate)
        let noise = (0..<Int(40 * rate)).map { _ in Float.random(in: -0.5...0.5) }
        let heard = VideoEnvelopeAlignment.envelope(samples: noise, sampleRate: rate)

        let match = try #require(VideoEnvelopeAlignment.bestLag(studio: studio, captured: heard, maximumLag: 1_000))

        #expect(match.correlation < 0.6)
    }
}
