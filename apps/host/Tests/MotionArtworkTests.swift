import Foundation
import Testing

@testable import CadenzaHost

struct MotionArtworkTests {
    private let base = URL(string: "https://mvod.itunes.apple.com/itunes-assets/HLSMusic126/v4/master.m3u8")!

    @Test func keepsTheLargestH264RenditionUnderTheBitrateCeiling() {
        let master = [
            "#EXTM3U",
            "#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=766942,_AVG-BANDWIDTH=766942,BANDWIDTH=887529,CODECS=\"avc1.64001f\"",
            "https://mvod.itunes.apple.com/a/486.m3u8",
            "#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=2125654,BANDWIDTH=2499558,CODECS=\"avc1.64001f\"",
            "https://mvod.itunes.apple.com/a/768.m3u8",
            "#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1859556,BANDWIDTH=2177387,CODECS=\"hvc1.2.20000000.L123.B0\"",
            "https://mvod.itunes.apple.com/a/hevc.m3u8",
            "#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=260081,BANDWIDTH=293430,CODECS=\"avc1.64001f\"",
            "rendition/360.m3u8",
        ].joined(separator: "\n")

        #expect(
            MotionPlaylist.h264Rendition(master, base: base)?.absoluteString
                == "https://mvod.itunes.apple.com/a/486.m3u8")
    }

    @Test func refusesMastersWithoutAnAffordableH264RenditionOrWithAnotherHost() {
        let tooLarge =
            "#EXT-X-STREAM-INF:BANDWIDTH=2499558,CODECS=\"avc1.64001f\"\nhttps://mvod.itunes.apple.com/a/768.m3u8"
        let hevcOnly =
            "#EXT-X-STREAM-INF:BANDWIDTH=500000,CODECS=\"hvc1.2.2\"\nhttps://mvod.itunes.apple.com/a/hevc.m3u8"
        let otherHost = "#EXT-X-STREAM-INF:BANDWIDTH=500000,CODECS=\"avc1.64001f\"\nhttps://example.com/a.m3u8"

        #expect(MotionPlaylist.h264Rendition(tooLarge, base: base) == nil)
        #expect(MotionPlaylist.h264Rendition(hevcOnly, base: base) == nil)
        #expect(MotionPlaylist.h264Rendition(otherHost, base: base) == nil)
    }

    @Test func mediaFileIsOneFinishedFileHoldingEverySegment() {
        let rendition = [
            "#EXTM3U", "#EXT-X-PLAYLIST-TYPE:VOD", "#EXT-X-MAP:URI=\"loop-.mp4\",BYTERANGE=\"897@0\"",
            "#EXTINF:4.5,", "#EXT-X-BYTERANGE:506631@897", "loop-.mp4",
            "#EXTINF:3.8,", "#EXT-X-BYTERANGE:389664@507528", "loop-.mp4", "#EXT-X-ENDLIST",
        ].joined(separator: "\n")
        let split = rendition.replacingOccurrences(of: "loop-.mp4\n#EXTINF:3.8", with: "other.mp4\n#EXTINF:3.8")
        let unfinished = rendition.replacingOccurrences(of: "#EXT-X-ENDLIST", with: "")

        #expect(MotionPlaylist.mediaFile(rendition, base: base)?.lastPathComponent == "loop-.mp4")
        #expect(MotionPlaylist.mediaFile(split, base: base) == nil)
        #expect(MotionPlaylist.mediaFile(unfinished, base: base) == nil)
    }

    @Test func onlyAnMP4FileReachesTheCache() {
        #expect(MotionPlaylist.isMP4(Data([0, 0, 0, 28]) + Data("ftypisom".utf8)))
        #expect(!MotionPlaylist.isMP4(Data("<html>".utf8)))
    }

    @Test func anAlbumMatchesOnlyWhenNameAndArtistAgree() throws {
        let search = Data(
            #"""
            {"results":{"albums":{"data":[
              {"id":"1499378108","attributes":{"name":"After Hours","artistName":"The Weeknd"}},
              {"id":"111","attributes":{"name":"After Hours","artistName":"Someone Else"}},
              {"id":"abc","attributes":{"name":"After Hours","artistName":"The Weeknd"}}
            ]}}}
            """#.utf8)

        #expect(CatalogAlbums.matchingIDs(search, album: "after hours", artist: "the weeknd") == ["1499378108"])
    }

    @Test func motionComesFromTheSquareRenditionOfTheAlbum() {
        let album = Data(
            #"""
            {"data":[{"attributes":{"editorialVideo":{
              "motionDetailTall":{"video":"https://mvod.itunes.apple.com/tall.m3u8"},
              "motionDetailSquare":{"video":"https://mvod.itunes.apple.com/square.m3u8"}}}}]}
            """#.utf8)
        let withoutMotion = Data(#"{"data":[{"attributes":{"name":"Starboy"}}]}"#.utf8)

        #expect(CatalogAlbums.motionMaster(album) == "https://mvod.itunes.apple.com/square.m3u8")
        #expect(CatalogAlbums.motionMaster(withoutMotion) == nil)
    }
}
