import Foundation

/// Apple's public catalog, as the browse service needs it. `Catalog` is the production source.
protocol BrowseCatalogSource: Sendable {
    func artist(id: String) async throws -> BrowseResult
    func album(id: String) async throws -> BrowseResult
    /// The album and the first artist a catalog song belongs to.
    func relations(ofSong id: String) async throws -> (album: String?, artist: String?)
    /// A catalog album whose name and artist both match exactly (ignoring case).
    func findAlbum(title: String, artist: String) async throws -> String?
    /// A catalog artist whose name matches exactly (ignoring case).
    func findArtist(name: String) async throws -> String?
}

/// Music's own library, read through the fixed automation script. `MusicLibraryBrowser` is the production source.
protocol BrowseLibrarySource: Sendable {
    func song(_ identity: SongIdentity) async throws -> Song
    func playlists() async throws -> [BrowsePlaylistSummary]
    func playlist(id: String) async throws -> (name: String, total: Int, songs: [Song])
    func songs(onAlbum album: String, artist: String) async throws -> [Song]
    func songs(byArtist artist: String) async throws -> [Song]
}

struct BrowsePlaylistSummary: Codable, Sendable, Equatable {
    var id: String
    var name: String
    var count: Int
}
