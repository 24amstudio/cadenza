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

    @Test func backgroundVocalsBecomeAnOverlappingTimedLine() throws {
        let ttml = """
            <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" itunes:timing="Word" xml:lang="en">
              <body><div>
                <p begin="1:40.883" end="1:46.681" itunes:key="L17"><span begin="1:40.883" end="1:41.211">You</span> <span begin="1:41.211" end="1:41.449">got</span> <span ttm:role="x-bg"><span begin="1:43.713" end="1:44.602">(Pearly</span> <span begin="1:44.602" end="1:46.681">whites)</span></span></p>
              </div></body>
            </tt>
            """
        let document = try TTMLDocument.parse(Data(ttml.utf8), occurrence: "occurrence")
        #expect(document.lines.map(\.id) == ["L17", "L17-bg0"])
        #expect(document.lines[0].text == "You got")
        #expect(document.lines[0].words.map(\.startMs) == [100_883, 101_211])
        #expect(document.lines[1].text == "(Pearly whites)")
        #expect(document.lines[1].startMs == 103_713)
        #expect(document.lines[1].endMs == 106_681)
    }

    @Test func untimedBackgroundVocalsStayInTheMainLine() throws {
        let ttml = """
            <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" itunes:timing="Line" xml:lang="en">
              <body><div>
                <p begin="10" end="14" itunes:key="L1">Main line <span ttm:role="x-bg">(echo)</span></p>
              </div></body>
            </tt>
            """
        let document = try TTMLDocument.parse(Data(ttml.utf8), occurrence: "occurrence")
        #expect(document.lines.map(\.text) == ["Main line (echo)"])
    }
}
