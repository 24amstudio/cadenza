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

    @Test func piecewiseSegmentsSkipStoryBreaksAndTrackShiftedOffsets() {
        let rate = 16_000.0
        let studioSamples = music(seconds: 16, sampleRate: rate)
        let studio = VideoEnvelopeAlignment.envelope(samples: studioSamples, sampleRate: rate)
        let firstHalf = Array(studio[0..<800])
        let secondHalf = Array(studio[800..<1600])
        let storyBreak = [Float](repeating: 0.02, count: 400)
        let intro = [Float](repeating: 0.01, count: 200)
        let captured = intro + firstHalf + storyBreak + secondHalf

        let segments = VideoEnvelopeAlignment.piecewiseSegments(
            studio: studio, captured: captured, chunkFrames: 400, minCorrelation: 0.85)

        #expect(segments.count == 2)
        #expect(segments[0].studioStartMs == 0)
        #expect(segments[0].studioEndMs == 8_000)
        #expect(segments[0].videoOffsetMs == 2_000)
        #expect(segments[1].studioStartMs == 8_000)
        #expect(segments[1].studioEndMs == 16_000)
        #expect(segments[1].videoOffsetMs == 6_000)
    }
}
