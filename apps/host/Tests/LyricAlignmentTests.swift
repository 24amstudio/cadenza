import Foundation
import Testing

@testable import CadenzaHost

struct LyricAlignmentTests {
    private func parse(_ body: String) throws -> LyricDocument {
        let ttml =
            #"<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div>\#(body)</div></body></tt>"#
        return try TTMLDocument.parse(Data(ttml.utf8), occurrence: "occurrence")
    }

    @Test func theFirstSingerStartsAndEveryOtherSingerEnds() throws {
        let document = try parse(
            """
            <p begin="1s" end="2s" itunes:key="L1" ttm:agent="v1">One</p>
            <p begin="3s" end="4s" itunes:key="L2" ttm:agent="v2">Two</p>
            <p begin="5s" end="6s" itunes:key="L3" ttm:agent="v1">Three</p>
            <p begin="7s" end="8s" itunes:key="L4" ttm:agent="v3">Four</p>
            """)

        #expect(document.lines.map(\.align) == [nil, "end", nil, "end"])
    }

    @Test func aDocumentWithoutAgentsOrWithOneAgentStaysAtTheStart() throws {
        let plain = try parse(#"<p begin="1s" end="2s" itunes:key="L1">One</p>"#)
        let solo = try parse(#"<p begin="1s" end="2s" itunes:key="L1" ttm:agent="v1">One</p>"#)

        #expect(plain.lines.allSatisfy { $0.align == nil })
        #expect(solo.lines.allSatisfy { $0.align == nil })
        #expect(try Wire.encode(solo.lines[0]).range(of: Data("align".utf8)) == nil)
    }
}
