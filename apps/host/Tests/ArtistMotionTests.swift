import Foundation
import Testing

@testable import CadenzaHost

struct ArtistMotionTests {
    private let search = Data(
        #"{"results":{"artists":{"data":[{"id":"111","attributes":{"name":"Payung Teduh"}},{"id":"222","attributes":{"name":"Payung Teduh Band"}}]}}}"#
            .utf8)

    @Test func anArtistIsMatchedOnlyByItsExactName() {
        #expect(CatalogArtists.matchingID(search, name: "payung teduh") == "111")
        #expect(CatalogArtists.matchingID(search, name: "Payung") == nil)
    }

    @Test func theWideArtistVideoIsPreferredAndTheSquareOneIsTheFallback() {
        let wide = Data(
            #"{"data":[{"attributes":{"editorialVideo":{"motionArtistWide":{"video":"https://example.test/wide.m3u8"},"motionDetailSquare":{"video":"https://example.test/square.m3u8"}}}}]}"#
                .utf8)
        let squareOnly = Data(
            #"{"data":[{"attributes":{"editorialVideo":{"motionDetailSquare":{"video":"https://example.test/square.m3u8"}}}}]}"#
                .utf8)

        #expect(CatalogArtists.motionMaster(wide) == "https://example.test/wide.m3u8")
        #expect(CatalogArtists.motionMaster(squareOnly) == "https://example.test/square.m3u8")
    }

    @Test func anArtistMotionRequestNeedsANameOfOneToTwoHundredCharacters() throws {
        let requestId = UUID().uuidString.lowercased()
        let head = #"{"version":1,"type":"artist.motion.get","request_id":"\#(requestId)""#
        let valid = head + #","artist_name":"Payung Teduh"}"#
        #expect(try ProtocolValidation.decode(Data(valid.utf8)).artistName == "Payung Teduh")

        let empty = head + #","artist_name":""}"#
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(empty.utf8)) }

        let withoutName = head + "}"
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(withoutName.utf8)) }
    }
}
