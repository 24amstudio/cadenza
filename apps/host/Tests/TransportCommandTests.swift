import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct TransportCommandTests {
    /// A Music that records every script call. `reply` answers a call, and `delayMs` is how long a call takes.
    @MainActor private final class FakeMusic {
        var calls: [[String]] = []
        var playing = true
        var shuffle = false
        var repeatMode = "off"
        var song = "native-a"
        // Number of status reads that still show the old playing state after a pause, as Music does for a moment.
        var staleReads = 0
        var delayMs = 0

        func status() -> String {
            let state = playing ? "playing" : "paused"
            return #"{"playing":\#(playing),"state":"\#(state)","volume":50,"position_ms":30000,"#
                + #""read_at_ms":\#(Int64(Date().timeIntervalSince1970 * 1_000)),"shuffle":\#(shuffle),"#
                + #""repeat":"\#(repeatMode)","song":{"source":"unknown","id":"\#(song)","title":"Song","#
                + #""artist":"Artist","album":"Album","duration_ms":200000}}"#
        }

        func run(_ arguments: [String]) async throws -> Data {
            calls.append(arguments)
            if delayMs > 0 { try await Task.sleep(for: .milliseconds(delayMs)) }
            switch arguments.first {
            case "pause":
                if staleReads == 0 { playing = false }
                return Data(#"{"dispatched":true,"status":\#(status())}"#.utf8)
            case "skip":
                song = "native-b"
                return Data(#"{"dispatched":true,"status":\#(status())}"#.utf8)
            case "shuffle":
                shuffle = arguments[1] == "true"
                return Data(#"{"dispatched":true,"status":\#(status())}"#.utf8)
            case "repeat":
                repeatMode = arguments[1]
                return Data(#"{"dispatched":true,"status":\#(status())}"#.utf8)
            default:
                if staleReads > 0 {
                    staleReads -= 1
                    if staleReads == 0 { playing = false }
                }
                return Data(status().utf8)
            }
        }
    }

    private struct Fixture {
        let coordinator: QueueCoordinator
        let music: FakeMusic
        let store: HostStore
        let remote: String
        let directory: URL
    }

    private func makeFixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadenza-transport-" + UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: "cadenza-transport-" + UUID().uuidString))
        let store = try HostStore(directory: directory, defaults: defaults)
        try store.beginEpoch()
        let (remote, _) = try store.pair(name: "Tablet")
        let fake = FakeMusic()
        let bridge = MusicBridge()
        bridge.scriptRunner = { try await fake.run($0) }
        let coordinator = QueueCoordinator(
            store: store, music: bridge, catalog: Catalog(credentials: store.credentials))
        await coordinator.refresh()
        fake.calls.removeAll()
        return Fixture(coordinator: coordinator, music: fake, store: store, remote: remote, directory: directory)
    }

    private func command(_ action: CommandAction, store: HostStore) throws -> Frame {
        var frame = Frame(type: "command")
        frame.commandId = UUID().uuidString.lowercased()
        frame.hostEpoch = store.epoch
        frame.expectedRevision = try store.revision
        frame.expiresAtHostMs = monotonicMs() + 900
        frame.action = action
        return frame
    }

    @Test func skipIsDispatchedBeforeAnyMusicReadSoItsDeadlineIsNotSpent() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        // Each Music read takes 300 ms, like a real osascript launch. Reading first would leave too little time.
        fixture.music.delayMs = 300
        let occurrence = try #require(fixture.coordinator.snapshot().current?.occurrenceId)

        let result = try await fixture.coordinator.execute(
            command(CommandAction(kind: "playback.skip", occurrenceId: occurrence), store: fixture.store),
            actor: fixture.remote)

        #expect(result.outcome == "applied")
        #expect(fixture.music.calls.first == ["skip"])
    }

    @Test func aStateReadThatLagsBehindAPauseDoesNotMakeItUnconfirmed() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        // Music still reports "playing" for the dispatch readback and the first polls, then settles.
        fixture.music.staleReads = 3
        fixture.music.playing = true

        let result = try await fixture.coordinator.execute(
            command(CommandAction(kind: "playback.pause"), store: fixture.store), actor: fixture.remote)

        #expect(result.outcome == "applied")
        #expect(try fixture.coordinator.snapshot().playing == false)
        #expect(fixture.music.calls.filter { $0 == ["status"] }.count >= 2)
    }

    @Test func shuffleAndRepeatReachMusicAndAppearInTheSnapshot() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let shuffled = try await fixture.coordinator.execute(
            command(CommandAction(kind: "playback.shuffle", enabled: true), store: fixture.store),
            actor: fixture.remote)
        let repeated = try await fixture.coordinator.execute(
            command(CommandAction(kind: "playback.repeat", mode: "one"), store: fixture.store),
            actor: fixture.remote)

        #expect(shuffled.outcome == "applied")
        #expect(repeated.outcome == "applied")
        #expect(fixture.music.calls.contains(["shuffle", "true"]))
        #expect(fixture.music.calls.contains(["repeat", "one"]))
        let snapshot = try fixture.coordinator.snapshot()
        #expect(snapshot.shuffle)
        #expect(snapshot.repeat == "one")
    }

    @Test func aModeChangedInsideMusicReachesTheNextSnapshot() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let before = try fixture.coordinator.snapshot()
        fixture.music.shuffle = true
        fixture.music.repeatMode = "all"

        await fixture.coordinator.refresh()

        let after = try fixture.coordinator.snapshot()
        #expect(!before.shuffle && before.repeat == "off")
        #expect(after.shuffle && after.repeat == "all")
        #expect(!after.permitsHeartbeat(comparedTo: before))
    }

    @Test func controlArgumentsRejectMalformedModes() throws {
        #expect(
            try MusicBridge.controlArguments(CommandAction(kind: "playback.shuffle", enabled: false)) == [
                "shuffle", "false",
            ])
        #expect(
            try MusicBridge.controlArguments(CommandAction(kind: "playback.repeat", mode: "all")) == ["repeat", "all"])
        #expect(throws: (any Error).self) {
            try MusicBridge.controlArguments(CommandAction(kind: "playback.repeat", mode: "sometimes"))
        }
        #expect(throws: (any Error).self) {
            try MusicBridge.controlArguments(CommandAction(kind: "playback.shuffle"))
        }
        #expect(throws: (any Error).self) {
            try MusicBridge.controlArguments(CommandAction(kind: "playback.format"))
        }
    }

    @Test func confirmationPollsUntilMusicShowsTheResultOrTheBudgetEnds() async throws {
        var reads = 0
        let action = CommandAction(kind: "playback.pause")
        let playing = MusicStatus(playing: true, state: "playing", volume: 50, positionMs: 0)
        let paused = MusicStatus(playing: false, state: "paused", volume: 50, positionMs: 0)

        let settled = await TransportConfirmation.awaitConfirmation(
            action, before: playing, first: playing, dispatchedAtMs: monotonicMs(), deadline: monotonicMs() + 1_000,
            intervalMs: 1
        ) {
            reads += 1
            return reads < 3 ? playing : paused
        }
        #expect(settled.confirmed?.playing == false)
        #expect(reads == 3)

        let neverSettled = await TransportConfirmation.awaitConfirmation(
            action, before: playing, first: playing, dispatchedAtMs: monotonicMs(), deadline: monotonicMs() + 40,
            intervalMs: 5
        ) { playing }
        #expect(neverSettled.confirmed == nil)
        #expect(neverSettled.last?.playing == true)
    }

    @Test func skipAndPreviousAreConfirmedByANewSongOrARestart() {
        let skip = CommandAction(kind: "playback.skip")
        let song = Song(source: "unknown", id: "native-a", title: "A", artist: "X")
        let other = Song(source: "unknown", id: "native-b", title: "B", artist: "X")
        let before = MusicStatus(playing: true, state: "playing", volume: 50, positionMs: 90_000, song: song)

        func confirmed(_ status: MusicStatus) -> Bool {
            TransportConfirmation.isConfirmed(skip, status: status, before: before, elapsedMs: 400)
        }

        #expect(!confirmed(MusicStatus(playing: true, state: "playing", volume: 50, positionMs: 90_400, song: song)))
        #expect(confirmed(MusicStatus(playing: true, state: "playing", volume: 50, positionMs: 400, song: other)))
        #expect(confirmed(MusicStatus(playing: true, state: "playing", volume: 50, positionMs: 400, song: song)))
        #expect(confirmed(MusicStatus(playing: false, state: "stopped", volume: 50, positionMs: 0)))
    }

    @Test func aLibrarySongMusicCannotFindIsReportedPlainlyNotAsARawAppleEventError() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let raw = CadenzaError.failure(
            "music_unavailable", "execution error: Error: Error: The library track is unavailable (-2700)")
        let bridge = MusicBridge()
        bridge.scriptRunner = { _ in throw raw }
        let coordinator = QueueCoordinator(
            store: fixture.store, music: bridge, catalog: Catalog(credentials: fixture.store.credentials))
        let identity = SongIdentity(source: "library", id: "0123456789ABCDEF")
        let stale = Song(source: "library", id: "0123456789ABCDEF", title: "Song", artist: "Artist", album: "Album")

        for metadata in [nil, stale] {
            do {
                try await coordinator.prepare(identity, metadata: metadata)
                Issue.record("An unresolvable library song was prepared.")
            } catch let error as CadenzaError {
                #expect(error.code == "not_found")
                #expect(!error.localizedDescription.contains("-2700"))
            }
        }
    }

    @Test func aMovedLibrarySongIsFoundAgainOnlyByItsOwnTitleArtistAndAlbum() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let bridge = MusicBridge()
        bridge.scriptRunner = { _ in
            Data(
                #"""
                [{"source":"library","id":"1111111111111111","title":"Song (Live)","artist":"Artist","album":"Album"},
                 {"source":"library","id":"2222222222222222","title":"Song","artist":"artist","album":"Other Album"},
                 {"source":"library","id":"3333333333333333","title":"song","artist":"Artist","album":"album"}]
                """#.utf8)
        }
        let coordinator = QueueCoordinator(
            store: fixture.store, music: bridge, catalog: Catalog(credentials: fixture.store.credentials))
        let remembered = Song(
            source: "library", id: "0123456789ABCDEF", title: "Song", artist: "Artist", album: "Album")

        #expect(try await coordinator.librarySong(matching: remembered)?.id == "3333333333333333")
        var unknown = remembered
        unknown.title = "Different"
        #expect(try await coordinator.librarySong(matching: unknown) == nil)
    }
}
