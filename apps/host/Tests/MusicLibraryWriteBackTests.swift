import Foundation
import Testing

@testable import CadenzaHost

struct MusicLibraryWriteBackTests {
    private let library = SongIdentity(source: "library", id: "AB1234567890CDEF")
    private let catalog = SongIdentity(source: "catalog", id: "958A4478EDBDEEF8")

    @Test func aFavoriteNamesOnlyALibrarySongAndItsFlag() throws {
        #expect(
            try MusicLibraryWriteBack.favoriteArguments(library, favorite: true) == [
                "favorite", "AB1234567890CDEF", "true",
            ])
        #expect(throws: CadenzaError.self) { try MusicLibraryWriteBack.favoriteArguments(catalog, favorite: true) }
        #expect(throws: CadenzaError.self) {
            try MusicLibraryWriteBack.favoriteArguments(SongIdentity(source: "library", id: "ab"), favorite: true)
        }
    }

    @Test func aPlaylistWriteTrimsItsNameAndRefusesCatalogSongsAndEmptyOrOversizedRequests() throws {
        #expect(
            try MusicLibraryWriteBack.playlistArguments(name: "  Cadenza Host  ", [library])
                == ["playlist-add", "Cadenza Host", "AB1234567890CDEF"])
        #expect(throws: CadenzaError.self) { try MusicLibraryWriteBack.playlistArguments(name: " ", [library]) }
        #expect(throws: CadenzaError.self) { try MusicLibraryWriteBack.playlistArguments(name: "Session", []) }
        #expect(throws: CadenzaError.self) { try MusicLibraryWriteBack.playlistArguments(name: "Session", [catalog]) }
        let tooMany = Array(repeating: library, count: MusicLibraryWriteBack.playlistTrackLimit + 1)
        #expect(throws: CadenzaError.self) { try MusicLibraryWriteBack.playlistArguments(name: "Session", tooMany) }
    }
}
