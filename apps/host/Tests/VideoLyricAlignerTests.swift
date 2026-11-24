import Testing

@testable import CadenzaHost

struct VideoLyricAlignerTests {
    @Test func aVideoWithinThreeSecondsOfTheStudioLengthNeedsNoAlignment() {
        #expect(!VideoLyricAligner.needsAlignment(studioDurationMs: 200_000, videoDurationMs: 203_000))
        #expect(!VideoLyricAligner.needsAlignment(studioDurationMs: 200_000, videoDurationMs: 197_000))
        #expect(VideoLyricAligner.needsAlignment(studioDurationMs: 200_000, videoDurationMs: 203_001))
    }

    @Test func aLyricInsideASegmentMovesByThatSegmentsOffsetAndTheUserNudge() {
        let segments = [
            VideoLyricAligner.Segment(studioStartMs: 0, studioEndMs: 60_000, videoOffsetMs: 0),
            VideoLyricAligner.Segment(studioStartMs: 60_000, studioEndMs: 120_000, videoOffsetMs: 90_000),
        ]

        #expect(
            VideoLyricAligner.videoTime(forStudioMs: 70_000, segments: segments, userOffsetMs: 500) == 160_500)
    }

    @Test func aLyricBetweenMusicalSegmentsIsHidden() {
        let segments = [
            VideoLyricAligner.Segment(studioStartMs: 0, studioEndMs: 10_000, videoOffsetMs: 0),
            VideoLyricAligner.Segment(studioStartMs: 20_000, studioEndMs: 30_000, videoOffsetMs: 0),
        ]

        #expect(VideoLyricAligner.videoTime(forStudioMs: 15_000, segments: segments, userOffsetMs: 0) == nil)
        #expect(VideoLyricAligner.videoTime(forStudioMs: 10_000, segments: segments, userOffsetMs: 0) == nil)
    }
}
