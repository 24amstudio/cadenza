import Foundation
import Testing

@testable import CadenzaHost

struct LyricTimingTests {
    @Test func subMinuteBareSecondTimesKeepLineAndWordStarts() throws {
        let ttml = """
            <tt xmlns="http://www.w3.org/ns/ttml" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" itunes:timing="Word" xml:lang="id">
              <body><div>
                <p begin="33.016" end="37.163" itunes:key="L1"><span begin="33.016" end="33.439">Tak</span> <span begin="33.439" end="34.039">terasa</span></p>
                <p begin="55.356" end="58.585" itunes:key="L2">Sedang cantik-cantiknya</p>
                <p begin="1:38.815" end="1:43.426" itunes:key="L3">Lalu mataku merasa malu</p>
              </div></body>
            </tt>
            """
        let document = try TTMLDocument.parse(Data(ttml.utf8), occurrence: "occurrence")
        #expect(document.lines.map(\.startMs) == [33_016, 55_356, 98_815])
        #expect(document.lines.map(\.endMs) == [37_163, 58_585, 103_426])
        #expect(document.lines[0].words.map(\.startMs) == [33_016, 33_439])
    }
}
