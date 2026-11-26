import Foundation
import Testing

@testable import CadenzaHost

struct LibraryCommandValidationTests {
    private func command(_ action: String) -> Data {
        let commandId = UUID().uuidString.lowercased()
        let epoch = UUID().uuidString.lowercased()
        let frame =
            #"{"version":1,"type":"command","command_id":"\#(commandId)","host_epoch":"\#(epoch)","#
            + #""expires_at_host_ms":9007199254740,"expected_revision":1,"action":\#(action)}"#
        return Data(frame.utf8)
    }

    @Test func aFavoriteOfALibrarySongIsAcceptedAndACatalogSongIsRefused() throws {
        let library = #"{"kind":"library.favorite","song":{"source":"library","id":"AB1234567890CDEF"},"enabled":true}"#
        let catalog = #"{"kind":"library.favorite","song":{"source":"catalog","id":"958A4478EDBDEEF8"},"enabled":true}"#

        #expect(try ProtocolValidation.decode(command(library)).action?.kind == "library.favorite")
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(command(catalog)) }
    }

    @Test func aSongWithExtraFieldsIsRefusedSoNoMetadataRidesAlong() throws {
        let extra =
            #"{"kind":"library.favorite","song":{"source":"library","id":"AB1234567890CDEF","title":"x"},"enabled":true}"#

        #expect(throws: (any Error).self) { try ProtocolValidation.decode(command(extra)) }
    }

    @Test func aPlaylistWriteNeedsANameAndLibrarySongsOnly() throws {
        let valid =
            #"{"kind":"library.addToPlaylist","name":"Cadenza Host","songs":[{"source":"library","id":"AB1234567890CDEF"}]}"#
        let catalog =
            #"{"kind":"library.addToPlaylist","name":"Cadenza Host","songs":[{"source":"catalog","id":"958A4478EDBDEEF8"}]}"#

        #expect(try ProtocolValidation.decode(command(valid)).action?.kind == "library.addToPlaylist")
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(command(catalog)) }
    }
}
