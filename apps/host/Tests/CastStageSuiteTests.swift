import Foundation
import Testing

@testable import CadenzaHost

struct CastStageSuiteTests {
    private let song = Song(
        source: "catalog", id: "1440657000", title: "Pedida", artist: "Akad", album: "Album", durationMs: 214_000,
        artworkUrl: nil)

    @Test func theQualityBadgeIsOmittedWhileTheTierIsUnknown() {
        #expect(StageTrackSuite.badge(for: "unknown") == nil)
        #expect(StageTrackSuite.badge(for: "hi_res_lossless") == "Hi-Res Lossless")
        #expect(StageTrackSuite.badge(for: "dolby_atmos") == "Dolby Atmos")
        #expect(StageTrackSuite.badge(for: "lossless") == "Lossless")
        #expect(StageTrackSuite.badge(for: "aac") == "AAC")
    }

    @Test func aSuiteIdIsStableOpaqueHexForASong() {
        let first = StageTrackSuite.suiteId(for: song.identity)
        #expect(first == StageTrackSuite.suiteId(for: song.identity))
        #expect(first.count == 24 && first.allSatisfy { $0.isHexDigit })
        #expect(!first.contains("1440657000"))
    }

    @Test func linesKeepTheirTimesWordsAndTranslationsAndCapTheirCount() {
        let lines = (0..<2_005).map { index in
            LyricLine(
                id: "line-\(index)", text: "t\(index)", startMs: Int64(index * 1_000),
                endMs: Int64(index * 1_000 + 900),
                words: [LyricWord(text: "t", startMs: 0, endMs: 10)], translation: "terj", align: "end")
        }
        let document = LyricDocument(
            occurrenceId: "occ", revision: "r", language: nil, translationSource: "x", lines: lines)
        let suite = StageTrackSuite.make(
            suiteId: "abc", song: song, quality: "lossless", document: document, mediaBase: "http://192.168.1.10:8765")
        #expect(suite.lines.count == StageTrackSuite.maximumLines)
        #expect(suite.lines[1].json["start_ms"] as? Int64 == 1_000)
        #expect(suite.lines[1].json["translation"] as? String == "terj")
        #expect(suite.lines[1].json["align"] as? String == "end")
        #expect(suite.artworkUrl == "http://192.168.1.10:8765/api/v1/cast/artwork/abc.jpg")
        #expect(suite.motionUrl == "http://192.168.1.10:8765/api/v1/cast/motion/abc.mp4")
    }
}
