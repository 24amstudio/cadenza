import Foundation
import Testing

@testable import CadenzaHost

struct MusicCodecTierTests {
    @Test func aStreamingAACFileReportsAACWhenMusicShowsNoBadge() {
        #expect(MusicQuality.tier(forFileKind: "Apple Music AAC audio file") == "aac")
        #expect(MusicQuality.tier(forFileKind: "Apple Lossless audio file") == nil)
        #expect(MusicQuality.tier(forFileKind: nil) == nil)
    }

    @Test func theStatusScriptsFileKindDecodesAndOlderScriptsStillDecode() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let kindJSON =
            #"{"playing":true,"state":"playing","volume":40,"position_ms":1000,"#
            + #""file_kind":"Apple Music AAC audio file"}"#
        let withKind = try decoder.decode(MusicStatus.self, from: Data(kindJSON.utf8))
        let older = try decoder.decode(
            MusicStatus.self,
            from: Data(#"{"playing":false,"state":"paused","volume":40,"position_ms":0}"#.utf8))

        #expect(withKind.fileKind == "Apple Music AAC audio file")
        #expect(older.fileKind == nil)
    }
}
