import Foundation
import Testing

@testable import CadenzaHost

struct MusicLiveRadioTests {
    private func decodeStatus(_ json: String) throws -> MusicStatus {
        try Wire.decode(MusicStatus.self, from: Data(json.utf8))
    }

    @Test func aBareStreamHasNoLengthAndGetsTheLiveArtistFallback() throws {
        let status = try decodeStatus(
            #"{"playing":true,"state":"playing","volume":40,"position_ms":0,"#
                + #""song":{"source":"unknown","id":"native-1","title":"","artist":"","album":"","#
                + #""duration_ms":null,"is_live_radio":true}}"#)

        #expect(status.isLiveRadio)
        #expect(status.song?.durationMs == nil)
        #expect(status.song?.artist == "Live Radio")
    }

    @Test func aStationKeepsTheMetadataItReports() throws {
        let status = try decodeStatus(
            #"{"playing":true,"state":"playing","volume":40,"position_ms":1250,"#
                + #""song":{"source":"unknown","id":"native-2","title":"Song","artist":"Artist","album":"Album","#
                + #""duration_ms":null,"artwork_url":null,"is_live_radio":true}}"#)

        #expect(status.isLiveRadio)
        #expect(status.song?.title == "Song")
        #expect(status.song?.artist == "Artist")
        #expect(status.song?.album == "Album")
        #expect(status.song?.durationMs == nil)
    }

    @Test func aSongWithALengthIsNotLive() throws {
        let status = try decodeStatus(
            #"{"playing":true,"state":"playing","volume":40,"position_ms":0,"#
                + #""song":{"source":"library","id":"AB1234567890CDEF","title":"Song","artist":"Artist","#
                + #""album":"Album","duration_ms":183125,"is_live_radio":false}}"#)

        #expect(!status.isLiveRadio)
        #expect(status.song?.durationMs == 183_125)
        #expect(status.song?.artist == "Artist")
    }

    @Test func aNonPositiveLengthIsLiveEvenWhenTheScriptClaimsItIsNot() throws {
        let status = try decodeStatus(
            #"{"playing":true,"state":"playing","volume":40,"position_ms":0,"#
                + #""song":{"source":"unknown","id":"native-3","title":"Song","artist":"Artist","album":"","#
                + #""duration_ms":0,"is_live_radio":false}}"#)

        #expect(status.isLiveRadio)
        #expect(status.song?.durationMs == nil)
    }

    @Test func anOlderScriptWithoutTheFlagClassifiesAStreamByItsMissingLength() throws {
        let status = try decodeStatus(
            #"{"playing":true,"state":"playing","volume":40,"position_ms":0,"#
                + #""song":{"source":"unknown","id":"native-4","title":"","artist":"","album":"","duration_ms":null}}"#)

        #expect(status.isLiveRadio)
        #expect(status.song?.artist == "Live Radio")
    }

    @Test func aStatusWithoutASongIsNotLive() throws {
        let status = try decodeStatus(#"{"playing":false,"state":"stopped","volume":40,"position_ms":0}"#)

        #expect(!status.isLiveRadio)
        #expect(status.song == nil)
    }

    @Test func thePlaybackSnapshotCarriesTheLiveFlagOnTheWire() throws {
        let station = Song(source: "unknown", id: "native-5", title: "Station", artist: "Live Radio")
        let playback = CurrentPlayback(
            occurrenceId: "11111111-1111-4111-8111-111111111111", entryId: nil, requestedBy: nil,
            requesterName: "Remote", song: station, positionMs: 0, sampledAtHostMs: 1, artworkPreview: nil,
            isLiveRadio: true)

        let json = String(decoding: try Wire.encode(playback), as: UTF8.self)

        #expect(json.contains(#""is_live_radio":true"#))
    }
}
