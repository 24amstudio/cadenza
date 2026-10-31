import Foundation
import Testing

@testable import CadenzaHost

struct CatalogSuggestionsTests {
    // Shaped like Apple's search/suggestions response: terms, a song top result, and an album top result.
    private let payload = #"""
        {"results":{"suggestions":[
          {"kind":"terms","searchTerm":"akademie für alte musik","displayTerm":"akademie für alte musik","source":"8"},
          {"kind":"topResults","content":{"id":"1318701282","type":"songs","href":"/v1/catalog/us/songs/1318701282",
            "attributes":{"name":"Akad","artistName":"Payung Teduh","albumName":"Ruang Tunggu","durationInMillis":258281,
            "url":"https://music.apple.com/us/album/akad/1318700857?i=1318701282",
            "artwork":{"url":"https://is1-ssl.mzstatic.com/image/thumb/x/{w}x{h}bb.jpg"}}}},
          {"kind":"topResults","content":{"id":"9","type":"albums","attributes":{"name":"AKAD"}}}
        ]}}
        """#

    @Test func termsAndSongTopResultsAreKeptAndOtherKindsAreIgnored() throws {
        let suggestions = CatalogSuggestions.parse(Data(payload.utf8))

        #expect(suggestions.terms == ["akademie für alte musik"])
        #expect(suggestions.songs.map(\.id) == ["1318701282"])
        let song = try #require(suggestions.songs.first)
        #expect(song.title == "Akad")
        #expect(song.album == "Ruang Tunggu")
        #expect(song.artworkUrl == "https://is1-ssl.mzstatic.com/image/thumb/x/400x400bb.jpg")
    }

    @Test func aMalformedPayloadProducesNoSuggestionsInsteadOfFailing() {
        #expect(CatalogSuggestions.parse(Data("not json".utf8)) == CatalogSuggestions(terms: [], songs: []))
    }

    @Test func aSuggestRequestNeedsItsQueryAndRequestIdentifier() throws {
        let requestId = UUID().uuidString.lowercased()
        let valid = #"{"version":1,"type":"search.suggest","request_id":"\#(requestId)","query":"akad"}"#
        #expect(try ProtocolValidation.decode(Data(valid.utf8)).query == "akad")

        let withoutQuery = #"{"version":1,"type":"search.suggest","request_id":"\#(requestId)"}"#
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(withoutQuery.utf8)) }
    }
}
