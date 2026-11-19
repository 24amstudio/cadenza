import Foundation

/// Answers `browse.get`: albums, artists, and playlists from Apple's catalog and Music's library. Results are cached in
/// memory, and a cache hit makes no request. At most two fetches run at once.
actor BrowseService {
    static let concurrentFetches = 2

    private let catalog: any BrowseCatalogSource
    private let library: any BrowseLibrarySource
    private let cache: BrowseCache
    private let gate = BrowseGate(limit: BrowseService.concurrentFetches)

    init(catalog: any BrowseCatalogSource, library: any BrowseLibrarySource, cache: BrowseCache = BrowseCache()) {
        self.catalog = catalog
        self.library = library
        self.cache = cache
    }

    func result(for request: BrowseRequest) async throws -> BrowseResult {
        let key = Self.key(request.kind, id: request.id, song: request.song)
        if let hit = await cache.result(for: key) { return hit }
        let (fetched, lifetime) = try await gate.run { try await self.fetch(request) }
        let result = fetched.bounded()
        await cache.store(result, for: key, lifetime: lifetime)
        // A lookup by song also answers a later lookup by the catalog ID it resolved to.
        let resolved = Self.key(result.kind, id: result.id, song: nil)
        if resolved != key, lifetime == BrowseCache.catalogLifetime {
            await cache.store(result, for: resolved, lifetime: lifetime)
        }
        return result
    }

    static func key(_ kind: String, id: String?, song: SongIdentity?) -> String {
        if let song { return "\(kind):song:\(song.source):\(song.id)" }
        return "\(kind):id:\(id ?? "")"
    }

    private func fetch(_ request: BrowseRequest) async throws -> (BrowseResult, TimeInterval) {
        switch request.kind {
        case "playlists": return (try await playlists(), BrowseCache.libraryLifetime)
        case "playlist": return (try await playlist(request.id ?? ""), BrowseCache.libraryLifetime)
        case "album", "artist":
            if let id = request.id {
                return (try await catalogResult(request.kind, id: id), BrowseCache.catalogLifetime)
            }
            guard let song = request.song else { throw Self.invalid }
            return try await resolve(request.kind, song: song)
        default: throw Self.invalid
        }
    }

    private static let invalid = CadenzaError.failure("invalid_command", "Choose an album, artist, or playlist.")

    private func catalogResult(_ kind: String, id: String) async throws -> BrowseResult {
        kind == "album" ? try await catalog.album(id: id) : try await catalog.artist(id: id)
    }

    private func playlists() async throws -> BrowseResult {
        let items = try await library.playlists().map { playlist in
            BrowseItem(
                type: "playlist", id: playlist.id, title: playlist.name,
                subtitle: playlist.count == 1 ? "1 song" : "\(playlist.count) songs")
        }
        return BrowseResult(
            kind: "playlists", id: "playlists", title: "Playlists",
            sections: [BrowseSection(id: "playlists", title: "Playlists", items: items)])
    }

    private func playlist(_ id: String) async throws -> BrowseResult {
        let playlist = try await library.playlist(id: id)
        return BrowseResult(
            kind: "playlist", id: id, title: playlist.name,
            subtitle: playlist.total == 1 ? "1 song" : "\(playlist.total) songs",
            sections: [BrowseSection(id: "songs", title: "Songs", items: playlist.songs.map(BrowseItem.song))])
    }

    /// An album or artist for a song. The catalog is tried first; a library song with no exact catalog match, or a
    /// catalog that cannot be reached, is answered from the library's own tracks instead.
    private func resolve(_ kind: String, song identity: SongIdentity) async throws -> (BrowseResult, TimeInterval) {
        if identity.source == "catalog" {
            let relations = try await catalog.relations(ofSong: identity.id)
            guard let id = kind == "album" ? relations.album : relations.artist else { throw Self.notFound }
            return (try await catalogResult(kind, id: id), BrowseCache.catalogLifetime)
        }
        let song = try await library.song(identity)
        if let id = try await optionalMatch(kind, song: song) {
            return (try await catalogResult(kind, id: id), BrowseCache.catalogLifetime)
        }
        let tracks =
            kind == "album"
            ? try await library.songs(onAlbum: song.album, artist: song.artist)
            : try await library.songs(byArtist: song.artist)
        guard !tracks.isEmpty, kind == "artist" || !song.album.isEmpty else { throw Self.notFound }
        let title = kind == "album" ? song.album : song.artist
        return (
            BrowseResult(
                kind: kind, id: identity.id, title: title, subtitle: kind == "album" ? song.artist : nil,
                sections: [BrowseSection(id: "songs", title: "Songs", items: tracks.map(BrowseItem.song))]),
            BrowseCache.libraryLifetime
        )
    }

    private static let notFound = CadenzaError.failure("not_found", "This item is not available to browse.")

    // An unreachable catalog is not an error for a library song: its own tracks are still shown.
    private func optionalMatch(_ kind: String, song: Song) async throws -> String? {
        do {
            if kind == "album" {
                return song.album.isEmpty ? nil : try await catalog.findAlbum(title: song.album, artist: song.artist)
            }
            return try await catalog.findArtist(name: song.artist)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CadenzaError where error.code == "catalog_unavailable" || error.code == "not_found" {
            return nil
        }
    }
}
