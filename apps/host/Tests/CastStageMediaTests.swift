import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct CastStageMediaTests {
    private let suiteId = "0123456789abcdef01234567"

    private func store(with entry: StageSuiteStore.Entry? = nil) -> StageSuiteStore {
        let store = StageSuiteStore()
        if let entry { store.register(entry) }
        return store
    }

    private func entry(video: URL? = nil, lyrics: LyricDocument? = nil) -> StageSuiteStore.Entry {
        StageSuiteStore.Entry(
            suiteId: suiteId, occurrenceId: "occ",
            suite: StageTrackSuite(
                trackId: suiteId, title: "t", artist: "a", album: "b", durationMs: 1_000, quality: nil,
                artworkUrl: nil, motionUrl: nil, lines: []),
            lyrics: lyrics, artwork: Data([0x89, 0x50, 0x4E, 0x47, 1]),
            motion: Data([0, 0, 0, 8, 0x66, 0x74, 0x79, 0x70]),
            videoFile: video)
    }

    @Test func aMediaPathNeedsAnOpaqueSuiteIdAndAKnownName() {
        #expect(StageMediaPath("/api/v1/cast/motion/\(suiteId).mp4") == .motion(suiteId: suiteId))
        #expect(StageMediaPath("/api/v1/cast/artwork/\(suiteId).jpg?x=1") == .artwork(suiteId: suiteId))
        #expect(StageMediaPath("/api/v1/cast/video/\(suiteId)/lyrics.vtt") == .lyrics(suiteId: suiteId))
        #expect(StageMediaPath("/api/v1/cast/video/\(suiteId)/video.mp4") == .video(suiteId: suiteId))
        #expect(StageMediaPath("/api/v1/cast/motion/catalog:1440657000.mp4") == nil)
        #expect(StageMediaPath("/api/v1/cast/motion/\(suiteId.uppercased()).mp4") == nil)
        #expect(StageMediaPath("/api/v1/cast/video/\(suiteId)/other.bin") == nil)
    }

    @Test func aMissingSuiteIsNotFoundAndNeverGuessed() {
        let relay = StageMediaRelay(store: store())
        #expect(relay.reply(to: "/api/v1/cast/motion/\(suiteId).mp4", rangeHeader: nil)?.status == 404)
    }

    @Test func artworkAndMotionAreServedWithTheirTypes() {
        let relay = StageMediaRelay(store: store(with: entry()))
        let artwork = relay.reply(to: "/api/v1/cast/artwork/\(suiteId).jpg", rangeHeader: nil)
        #expect(artwork?.status == 200)
        #expect(artwork?.contentType == "image/png")
        let motion = relay.reply(to: "/api/v1/cast/motion/\(suiteId).mp4", rangeHeader: nil)
        #expect(motion?.contentType == "video/mp4")
    }

    @Test func lyricsAreRenderedAtRequestTimeWithTheSavedNudgeAndLipSync() {
        let line = LyricLine(id: "1", text: "Hello", startMs: 1_000, endMs: 2_000, translation: "Halo")
        let lyrics = LyricDocument(
            occurrenceId: "occ", revision: "r", language: "en", translationSource: "x", lines: [line],
            userOffsetMs: 500)
        let store = store(with: entry(lyrics: lyrics))
        store.lipSyncOffsetMs = { 100 }
        let vtt = store.lyricsText(for: suiteId) ?? ""
        #expect(vtt.hasPrefix("WEBVTT"))
        #expect(vtt.contains("00:00:01.600 --> 00:00:02.600"))
        #expect(vtt.contains("Halo"))
    }

    @Test func aLocalVideoIsServedInBoundedRanges() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "stage-video-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data((0..<100).map { UInt8($0) }).write(to: file)
        let relay = StageMediaRelay(store: store(with: entry(video: file)))
        let path = "/api/v1/cast/video/\(suiteId)/video.mp4"

        let partial = try #require(relay.reply(to: path, rangeHeader: "bytes=10-19"))
        #expect(partial.status == 206)
        #expect(partial.body == (10..<20).map { UInt8($0) })
        #expect(partial.headers.contains("Content-Range: bytes 10-19/100"))

        let unsatisfiable = try #require(relay.reply(to: path, rangeHeader: "bytes=500-600"))
        #expect(unsatisfiable.status == 416)
        #expect(unsatisfiable.headers.contains("Content-Range: bytes */100"))
    }
}
