import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct SingPageTests {
    private final class Sink {
        var frames: [Data] = []
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func state(_ occurrence: String, positionMs: Int64, playing: Bool = true) -> SingPageState {
        SingPageState(
            occurrenceId: occurrence, title: "Song", artist: "Artist", positionMs: positionMs, playing: playing)
    }

    private func lyrics(_ occurrence: String, revision: String = "1", userOffsetMs: Int? = nil) -> LyricDocument {
        LyricDocument(
            occurrenceId: occurrence, revision: revision, language: nil, translationSource: "", lines: [],
            userOffsetMs: userOffsetMs)
    }

    @Test func theSingWindowIsWantedOnlyForTheHostOutputWhileASongPlaysUnlessTheSongWasClosed() {
        #expect(
            SingPageVisibility.shouldShow(
                target: .hostDisplay, currentOccurrenceId: "a", dismissedOccurrenceId: nil))
        #expect(
            !SingPageVisibility.shouldShow(
                target: .castTransmitter, currentOccurrenceId: "a", dismissedOccurrenceId: nil))
        #expect(
            !SingPageVisibility.shouldShow(
                target: .hostDisplay, currentOccurrenceId: nil, dismissedOccurrenceId: nil))
        #expect(
            !SingPageVisibility.shouldShow(
                target: .hostDisplay, currentOccurrenceId: "a", dismissedOccurrenceId: "a"))
        #expect(
            SingPageVisibility.shouldShow(
                target: .hostDisplay, currentOccurrenceId: "b", dismissedOccurrenceId: "a"))
    }

    @Test func theLyricClockSubtractsTheLipSyncAndTheSavedNudge() {
        let current = CurrentPlayback(
            occurrenceId: "a", requesterName: "Remote", song: Song(source: "catalog", id: "1", title: "T", artist: "A"),
            positionMs: 10_000, sampledAtHostMs: 0)
        let state = SingPageState.make(from: current, playing: true, lipSyncOffsetMs: 150, userOffsetMs: -250)
        #expect(state.positionMs == 10_100)
        #expect(state.occurrenceId == "a")
        #expect(state.title == "T")
        #expect(state.artist == "A")
    }

    @Test func aPageThatConnectsLateGetsTheLyricsAndTheLatestStateAtOnce() throws {
        let feed = SingPageFeed()
        let sink = Sink()
        feed.update(state: state("a", positionMs: 4_000), lyrics: lyrics("a"))
        _ = feed.attach { data in
            sink.frames.append(data)
            return true
        }
        let types = try sink.frames.map { try #require(try object($0)["type"] as? String) }
        #expect(types == ["lyrics", "sing_state"])
        let latest = try object(try #require(sink.frames.last))
        #expect(latest["position_ms"] as? Int == 4_000)
        #expect(latest["playing"] as? Bool == true)
    }

    @Test func theLyricsGoOutOncePerRevisionAndTheStateWhenItChanges() throws {
        let feed = SingPageFeed()
        let sink = Sink()
        _ = feed.attach { data in
            sink.frames.append(data)
            return true
        }
        feed.update(state: state("a", positionMs: 1_000), lyrics: lyrics("a"))
        feed.update(state: state("a", positionMs: 2_000), lyrics: lyrics("a"))
        feed.update(state: state("a", positionMs: 2_000), lyrics: lyrics("a"))
        feed.update(state: state("a", positionMs: 3_000), lyrics: lyrics("a", revision: "2"))
        let types = try sink.frames.map { try #require(try object($0)["type"] as? String) }
        #expect(types == ["lyrics", "sing_state", "sing_state", "lyrics", "sing_state"])
    }

    @Test func aNudgeChangeSendsTheLyricsAgain() throws {
        let feed = SingPageFeed()
        let sink = Sink()
        _ = feed.attach { data in
            sink.frames.append(data)
            return true
        }
        feed.update(state: state("a", positionMs: 1_000), lyrics: lyrics("a", userOffsetMs: 0))
        feed.update(state: state("a", positionMs: 1_000), lyrics: lyrics("a", userOffsetMs: 300))
        let types = try sink.frames.map { try #require(try object($0)["type"] as? String) }
        #expect(types == ["lyrics", "sing_state", "lyrics"])
    }

    @Test func aDetachedPageReceivesNothingMore() {
        let feed = SingPageFeed()
        let sink = Sink()
        let id = feed.attach { data in
            sink.frames.append(data)
            return true
        }
        feed.detach(id)
        feed.update(state: state("a", positionMs: 1_000), lyrics: lyrics("a"))
        #expect(sink.frames.isEmpty)
    }

    @Test func theStateCarriesTheSnakeCaseWireNames() throws {
        let feed = SingPageFeed()
        let sink = Sink()
        _ = feed.attach { data in
            sink.frames.append(data)
            return true
        }
        feed.update(state: state("occurrence-1", positionMs: 7_500, playing: false), lyrics: nil)
        let frame = try object(try #require(sink.frames.first))
        #expect(frame["type"] as? String == "sing_state")
        #expect(frame["occurrence_id"] as? String == "occurrence-1")
        #expect(frame["position_ms"] as? Int == 7_500)
        #expect(frame["playing"] as? Bool == false)
    }
}
