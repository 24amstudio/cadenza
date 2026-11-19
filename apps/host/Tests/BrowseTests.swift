import Foundation
import Synchronization
import Testing

@testable import CadenzaHost

struct BrowseParsingTests {
    // Shaped like artists/{id}?views=top-songs,full-albums,singles&extend=artistBio.
    private let artistPage = #"""
        {"data":[{"id":"159260351","type":"artists","attributes":{
          "name":"Artist","genreNames":["Pop","Music"],"artistBio":"<b>Wrote</b> songs.\n\nToured <i>widely</i>.",
          "artwork":{"url":"https://is1-ssl.mzstatic.com/image/thumb/a/{w}x{h}{c}.{f}"}},
          "views":{
            "top-songs":{"data":[{"id":"11","type":"songs","attributes":{"name":"Hit","artistName":"Artist",
              "albumName":"First","durationInMillis":180000,"url":"https://music.apple.com/us/album/hit/10?i=11",
              "artwork":{"url":"https://is1-ssl.mzstatic.com/image/thumb/s/{w}x{h}bb.jpg"}}},
              {"id":"12","type":"music-videos","attributes":{"name":"Clip","artistName":"Artist"}}]},
            "full-albums":{"data":[{"id":"10","type":"albums","attributes":{"name":"First","releaseDate":"2019-05-01",
              "trackCount":12,"artwork":{"url":"https://is1-ssl.mzstatic.com/image/thumb/f/{w}x{h}bb.jpg"}}}]},
            "singles":{"data":[{"id":"20","type":"albums","attributes":{"name":"One","releaseDate":"2021-01-01",
              "isSingle":true}}]}}}]}
        """#

    @Test func anArtistPageBecomesSongsAlbumsAndSinglesWithAPlainBiography() throws {
        let result = try #require(BrowseCatalogParsing.artist(main: Data(artistPage.utf8)))

        #expect(result.kind == "artist" && result.id == "159260351" && result.title == "Artist")
        #expect(result.subtitle == "Pop")
        #expect(result.detail == "Wrote songs. Toured widely.")
        #expect(result.artworkUrl == "https://is1-ssl.mzstatic.com/image/thumb/a/400x400bb.jpg")
        #expect(result.sections.map(\.id) == ["top_songs", "albums", "singles"])
        // The music video is not a playable song.
        #expect(result.songs.map(\.id) == ["11"])
        #expect(result.sections[1].items.first?.subtitle == "2019 · 12 songs")
        #expect(result.sections[2].items.first?.subtitle == "2021 · Single")
    }

    @Test func aPayloadWithoutAnItemIsNotAResult() {
        #expect(BrowseCatalogParsing.artist(main: Data(#"{"data":[]}"#.utf8)) == nil)
        #expect(BrowseCatalogParsing.album(Data("not json".utf8)) == nil)
    }

    @Test func aBoundedResultKeepsTheWireLimits() {
        let songs = (1...150).map { BrowseItem.song(Song(source: "catalog", id: String($0), title: "T", artist: "A")) }
        let albums = (1...90).map {
            BrowseItem(type: "album", id: String($0), title: String(repeating: "x", count: 900))
        }
        let bounded = BrowseResult(
            kind: "artist", id: "1", title: "A",
            sections: [
                BrowseSection(id: "top_songs", title: "Top", items: songs),
                BrowseSection(id: "albums", title: "Albums", items: albums),
            ]
        ).bounded()

        #expect(bounded.sections[0].items.count == BrowseResult.maximumSongs)
        #expect(bounded.sections[1].items.count == BrowseResult.maximumAlbums)
        #expect(bounded.sections[1].items[0].title?.count == 500)
    }
}

extension BrowseParsingTests {
    @Test func aBluetoothResultFitsOneSmallFrameWithWholeItemsAndNoDetail() throws {
        let title = String(repeating: "T", count: 300)
        let songs = (1...100).map {
            BrowseItem.song(Song(source: "catalog", id: String($0), title: title, artist: "A"))
        }
        let full = BrowseResult(
            kind: "artist", id: "1", title: "A", detail: String(repeating: "bio ", count: 100),
            sections: [BrowseSection(id: "top_songs", title: "Top", items: songs)])

        let lan = full.bounded()
        let ble = full.bounded(forBluetooth: true)
        let frame = Frame(type: "browse.result", requestId: UUID().uuidString.lowercased(), browse: .result(ble))
        let encoded = try Wire.encode(frame)

        #expect(lan.sections[0].items.count == 100 && lan.detail != nil)
        #expect(encoded.count <= BrowseResult.maximumBluetoothFrameBytes)
        #expect(!ble.sections[0].items.isEmpty && ble.sections[0].items.count < 100)
        #expect(ble.detail == nil)
        // The frame is still whole JSON that decodes to the same items it kept.
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let items = ((json?["browse"] as? [String: Any])?["sections"] as? [[String: Any]])?.first?["items"] as? [Any]
        #expect(items?.count == ble.sections[0].items.count)
    }
}

struct BrowseCacheTests {
    private func result(_ id: String) -> BrowseResult {
        BrowseResult(kind: "album", id: id, title: id, sections: [])
    }

    @Test func anEntryExpiresAfterItsLifetime() async {
        let now = Mutex<TimeInterval>(0)
        let cache = BrowseCache(now: { now.withLock { $0 } })
        await cache.store(result("a"), for: "a", lifetime: 60)

        now.withLock { $0 = 59 }
        #expect(await cache.result(for: "a")?.id == "a")
        now.withLock { $0 = 61 }
        #expect(await cache.result(for: "a") == nil)
    }

    @Test func theLeastRecentlyUsedEntryLeavesWhenTheCacheIsFull() async {
        let cache = BrowseCache(capacity: 2, now: { 0 })
        await cache.store(result("a"), for: "a", lifetime: 60)
        await cache.store(result("b"), for: "b", lifetime: 60)
        _ = await cache.result(for: "a")
        await cache.store(result("c"), for: "c", lifetime: 60)

        #expect(await cache.result(for: "b") == nil)
        #expect(await cache.result(for: "a") != nil)
        #expect(await cache.result(for: "c") != nil)
    }
}

private final class FetchCounter: Sendable {
    private let state = Mutex((fetches: 0, active: 0, peak: 0))
    var fetches: Int { state.withLock { $0.fetches } }
    var peak: Int { state.withLock { $0.peak } }

    func begin() {
        state.withLock {
            $0.fetches += 1
            $0.active += 1
            $0.peak = max($0.peak, $0.active)
        }
    }

    func end() { state.withLock { $0.active -= 1 } }
}

private struct StubCatalog: BrowseCatalogSource {
    let counter = FetchCounter()
    var albumID: String? = "10"
    var failure: CadenzaError?

    func album(id: String) async throws -> BrowseResult {
        counter.begin()
        defer { counter.end() }
        try await Task.sleep(for: .milliseconds(20))
        if let failure { throw failure }
        return BrowseResult(kind: "album", id: id, title: "Album \(id)", sections: [])
    }

    func artist(id: String) async throws -> BrowseResult {
        BrowseResult(kind: "artist", id: id, title: "Artist \(id)", sections: [])
    }

    func relations(ofSong id: String) async throws -> (album: String?, artist: String?) { (albumID, nil) }

    func findAlbum(title: String, artist: String) async throws -> String? {
        if let failure { throw failure }
        return albumID
    }

    func findArtist(name: String) async throws -> String? { nil }
}

private struct StubLibrary: BrowseLibrarySource {
    var tracks: [Song] = []

    func song(_ identity: SongIdentity) async throws -> Song {
        Song(source: "library", id: identity.id, title: "Local", artist: "Band", album: "Demo")
    }

    func playlists() async throws -> [BrowsePlaylistSummary] { [] }
    func playlist(id: String) async throws -> (name: String, total: Int, songs: [Song]) { ("P", 0, []) }
    func songs(onAlbum album: String, artist: String) async throws -> [Song] { tracks }
    func songs(byArtist artist: String) async throws -> [Song] { tracks }
}

struct BrowseServiceTests {
    private let librarySong = SongIdentity(source: "library", id: "AB1234567890CDEF")

    @Test func aCacheHitMakesNoRequestAndASongLookupAnswersTheLaterIDLookup() async throws {
        let catalog = StubCatalog()
        let service = BrowseService(catalog: catalog, library: StubLibrary(), cache: BrowseCache(now: { 0 }))

        let bySong = try await service.result(
            for: BrowseRequest(kind: "album", song: SongIdentity(source: "catalog", id: "5")))
        _ = try await service.result(for: BrowseRequest(kind: "album", song: SongIdentity(source: "catalog", id: "5")))
        let byID = try await service.result(for: BrowseRequest(kind: "album", id: "10"))

        #expect(bySong.id == "10" && byID.id == "10")
        #expect(catalog.counter.fetches == 1)
    }

    @Test func aLibrarySongFallsBackToItsLibraryTracksWhenTheCatalogCannotBeReached() async throws {
        let catalog = StubCatalog(failure: .failure("catalog_unavailable", "offline"))
        let track = Song(source: "library", id: "1111111111111111", title: "Local", artist: "Band", album: "Demo")
        let service = BrowseService(
            catalog: catalog, library: StubLibrary(tracks: [track]), cache: BrowseCache(now: { 0 }))

        let result = try await service.result(for: BrowseRequest(kind: "album", song: librarySong))

        #expect(result.title == "Demo" && result.subtitle == "Band")
        #expect(result.songs == [track])
    }

    @Test func anItemWithNoCatalogMatchAndNoLibraryTracksIsNotFound() async {
        let catalog = StubCatalog(albumID: nil)
        let service = BrowseService(catalog: catalog, library: StubLibrary(), cache: BrowseCache(now: { 0 }))

        await #expect(throws: CadenzaError.self) {
            try await service.result(for: BrowseRequest(kind: "album", song: librarySong))
        }
    }

    @Test func atMostTwoCatalogFetchesRunAtOnce() async throws {
        let catalog = StubCatalog()
        let service = BrowseService(catalog: catalog, library: StubLibrary(), cache: BrowseCache(now: { 0 }))

        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in 1...6 {
                group.addTask { _ = try await service.result(for: BrowseRequest(kind: "album", id: String(id))) }
            }
            try await group.waitForAll()
        }

        #expect(catalog.counter.fetches == 6)
        #expect(catalog.counter.peak == 2)
    }
}

struct BrowseProtocolTests {
    private let id = UUID().uuidString.lowercased()

    private func browse(_ body: String) throws -> Frame {
        try ProtocolValidation.decode(
            Data(#"{"version":1,"type":"browse.get","request_id":"\#(id)","browse":\#(body)}"#.utf8))
    }

    @Test func browseRequestsNameExactlyOneSource() throws {
        let frame = try browse(#"{"kind":"album","song":{"source":"library","id":"AB1234567890CDEF"}}"#)
        guard case .request(let request)? = frame.browse else {
            Issue.record("Expected a browse request")
            return
        }
        #expect(request.kind == "album" && request.song?.id == "AB1234567890CDEF")
        _ = try browse(#"{"kind":"playlists"}"#)
        _ = try browse(#"{"kind":"artist","id":"159260351"}"#)

        for invalid in [
            #"{"kind":"album","id":"1","song":{"source":"catalog","id":"1"}}"#, #"{"kind":"album"}"#,
            #"{"kind":"playlist","id":"1"}"#, #"{"kind":"playlists","id":"1"}"#, #"{"kind":"genre","id":"1"}"#,
        ] {
            #expect(throws: (any Error).self) { try browse(invalid) }
        }
    }

    @Test func aSnapshotAlwaysReportsShuffleAndRepeat() throws {
        let snapshot = HostSnapshot(
            hostId: id, hostEpoch: id, revision: 0, sequence: 1, hostTimeMs: 0, allowCrossRemoteEdits: false,
            playing: false, volume: 50, current: nil, queue: [], totalRemainingMs: nil, shuffle: true, repeat: "all")
        let object = try #require(JSONSerialization.jsonObject(with: Wire.encode(snapshot)) as? [String: Any])
        #expect(object["shuffle"] as? Bool == true)
        #expect(object["repeat"] as? String == "all")

        let idle = HostSnapshot(
            hostId: id, hostEpoch: id, revision: 0, sequence: 1, hostTimeMs: 0, allowCrossRemoteEdits: false,
            playing: false, volume: 50, current: nil, queue: [], totalRemainingMs: nil)
        #expect(idle.shuffle == false && idle.repeat == "off")
    }

    @Test func playbackModeCommandsCarryOnlyTheirOwnField() throws {
        func command(_ action: String) throws -> Frame {
            try ProtocolValidation.decode(
                Data(
                    #"{"version":1,"type":"command","command_id":"\#(id)","host_epoch":"\#(id)","expires_at_host_ms":900,"expected_revision":0,"action":\#(action)}"#
                        .utf8))
        }

        #expect(try command(#"{"kind":"playback.shuffle","enabled":true}"#).action?.enabled == true)
        #expect(try command(#"{"kind":"playback.repeat","mode":"one"}"#).action?.mode == "one")
        for invalid in [
            #"{"kind":"playback.shuffle","enabled":1}"#, #"{"kind":"playback.shuffle"}"#,
            #"{"kind":"playback.repeat","mode":"forever"}"#,
            #"{"kind":"playback.repeat","mode":"all","occurrence_id":"\#(id)"}"#,
        ] {
            #expect(throws: (any Error).self) { try command(invalid) }
        }
    }
}
