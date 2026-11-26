import Foundation
import Testing

@testable import CadenzaHost

struct VideoStudioMatchTests {
    private func song(_ id: String, _ title: String, _ artist: String, _ durationMs: Int64?) -> Song {
        Song(source: "catalog", id: id, title: title, artist: artist, durationMs: durationMs)
    }

    @Test func aStudioTrackWithTheSameTitleArtistAndLengthIsTheLyricSource() {
        let video = song(
            "626140098", "Pedida perfeita (Tararatata) [feat. Anna Torres]", "Akad, Flavel & Neto & Teetoff", 180_200)
        let studio = song("100", "Pedida perfeita (Tararatata)", "Akad", 179_500)
        let otherSong = song("200", "Pedida perfeita (Tararatata)", "Someone Else", 179_500)
        let longer = song("300", "Pedida perfeita (Tararatata)", "Akad", 170_000)

        #expect(VideoStudioMatch.pick(video: video, candidates: [otherSong, longer, studio])?.id == "100")
    }

    @Test func aVideoLongerThanItsStudioTrackByMoreThanTheToleranceIsNotMatched() {
        let video = song("626140098", "Song", "Artist", 215_000)
        let studio = song("100", "Song", "Artist", 180_000)

        #expect(VideoStudioMatch.pick(video: video, candidates: [studio]) == nil)
    }

    @Test func aVideoWithoutItsLengthIsNotMatched() {
        let video = song("626140098", "Song", "Artist", nil)
        let studio = song("100", "Song", "Artist", 180_000)

        #expect(VideoStudioMatch.pick(video: video, candidates: [studio]) == nil)
    }
}
