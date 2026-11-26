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

    @Test func localDRMFreeVideoAcceptsOnlyExistingMP4OrM4VFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cadenza-local-video-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mp4 = dir.appending(path: "clip.mp4")
        let m4v = dir.appending(path: "clip.m4v")
        let txt = dir.appending(path: "note.txt")
        try Data([0]).write(to: mp4)
        try Data([0]).write(to: m4v)
        try Data([0]).write(to: txt)

        #expect(MusicBridge.safeLocalVideoURL(mp4.path)?.lastPathComponent == "clip.mp4")
        #expect(MusicBridge.safeLocalVideoURL(m4v.absoluteString)?.lastPathComponent == "clip.m4v")
        #expect(MusicBridge.safeLocalVideoURL(txt.path) == nil)
        #expect(MusicBridge.safeLocalVideoURL(dir.path) == nil)
    }
}
