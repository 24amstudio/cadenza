import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct VideoPlaybackTests {
    private let url = "https://music.apple.com/us/music-video/pedida-perfeita/626140098"

    @Test func aMusicVideoLinkOpensOnlyWhenItNamesThatVideo() throws {
        let video = Song(
            source: "catalog", id: "626140098", title: "Pedida", artist: "Akad", url: url, mediaType: .musicVideo)
        #expect(
            try MusicBridge.musicLink(for: video).absoluteString
                == "music://music.apple.com/us/music-video/pedida-perfeita/626140098")

        let other = Song(
            source: "catalog", id: "999", title: "Pedida", artist: "Akad", url: url, mediaType: .musicVideo)
        #expect(throws: (any Error).self) { try MusicBridge.musicLink(for: other) }
    }

    @Test func aVideoPlayRequestNamesOnlyACatalogIdentity() throws {
        let requestId = UUID().uuidString.lowercased()
        let identity = #""song":{"source":"catalog","id":"626140098"}"#
        let valid = #"{"version":1,"type":"video.play","request_id":"\#(requestId)",\#(identity)}"#
        #expect(try ProtocolValidation.decode(Data(valid.utf8)).song?.id == "626140098")

        let withTitle =
            #"{"version":1,"type":"video.play","request_id":"\#(requestId)","song":{"source":"catalog","id":"626140098","title":"x"}}"#
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(withTitle.utf8)) }
    }
}
