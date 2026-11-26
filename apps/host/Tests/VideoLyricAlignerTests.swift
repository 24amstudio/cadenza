import Foundation
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

    @Test func remapRewritesTimedLinesAndDropsStoryBreakLines() {
        let segments = [
            VideoLyricAligner.Segment(studioStartMs: 0, studioEndMs: 10_000, videoOffsetMs: 2_000),
            VideoLyricAligner.Segment(studioStartMs: 20_000, studioEndMs: 30_000, videoOffsetMs: 6_000),
        ]
        let doc = LyricDocument(
            occurrenceId: "occ-1", revision: "rev-1", language: "en", translationSource: "none",
            lines: [
                LyricLine(
                    id: "1", text: "Verse 1", startMs: 5_000, endMs: 8_000,
                    words: [LyricWord(text: "Verse", startMs: 5_000, endMs: 6_000)]),
                LyricLine(id: "2", text: "Break", startMs: 15_000, endMs: 18_000),
                LyricLine(id: "3", text: "Chorus", startMs: 21_000, endMs: 25_000),
            ])

        let mapped = VideoLyricAligner.remap(doc, segments: segments)

        #expect(mapped.lines.count == 2)
        #expect(mapped.lines[0].startMs == 7_000)
        #expect(mapped.lines[0].words.first?.startMs == 7_000)
        #expect(mapped.lines[1].text == "Chorus")
        #expect(mapped.lines[1].startMs == 27_000)
    }

    @MainActor @Test func alignmentStorePreservesOffsetsAndSegmentsIndependently() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cadenza-align-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try Database(url: dir.appending(path: "test.sqlite"))
        let store = LyricOffsetStore(database: db)
        let id = SongIdentity(source: "catalog", id: "999")
        let segments = [VideoLyricAligner.Segment(studioStartMs: 0, studioEndMs: 50_000, videoOffsetMs: 4_500)]

        try store.save(500, for: id, at: Date())
        try store.saveAlignment(VideoAlignmentRecord(studioSongId: "111", segments: segments), for: id, at: Date())
        #expect(try store.offset(for: id) == 500)
        #expect(try store.alignment(for: id)?.segments == segments)

        try store.save(-500, for: id, at: Date())
        #expect(try store.offset(for: id) == -500)
        #expect(try store.alignment(for: id)?.studioSongId == "111")
    }
}
