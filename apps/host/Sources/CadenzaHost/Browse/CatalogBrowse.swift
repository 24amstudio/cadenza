import Foundation

extension Catalog: BrowseCatalogSource {
    func artist(id: String) async throws -> BrowseResult {
        let main = try await request(
            path: "artists/\(id)",
            query: [
                URLQueryItem(name: "views", value: "top-songs,full-albums,singles"),
                URLQueryItem(name: "extend", value: "artistBio"),
            ], missingIsNotFound: true)
        guard var result = BrowseCatalogParsing.artist(main: main) else { throw Self.noSuchItem }
        // A view holds ten items. The full list is fetched only for a view that has more.
        let more = Self.moreViews(main)
        let topSongs = try await view("top-songs", of: id, limit: 50, if: more)
        let albums = try await view("full-albums", of: id, limit: BrowseResult.maximumAlbums, if: more)
        if topSongs != nil || albums != nil {
            result = BrowseCatalogParsing.artist(main: main, topSongs: topSongs, albums: albums) ?? result
        }
        _ = remember(result.songs)
        return result
    }

    func album(id: String) async throws -> BrowseResult {
        let data = try await request(
            path: "albums/\(id)", query: [URLQueryItem(name: "include", value: "tracks,artists")],
            missingIsNotFound: true)
        guard let result = BrowseCatalogParsing.album(data) else { throw Self.noSuchItem }
        _ = remember(result.songs)
        return result
    }

    func relations(ofSong id: String) async throws -> (album: String?, artist: String?) {
        let data = try await request(
            path: "songs/\(id)", query: [URLQueryItem(name: "include", value: "albums,artists")],
            missingIsNotFound: true)
        return BrowseCatalogParsing.relations(data)
    }

    func findAlbum(title: String, artist: String) async throws -> String? {
        let found = try await request(
            path: "search",
            query: [
                URLQueryItem(name: "term", value: String("\(title) \(artist)".prefix(200))),
                URLQueryItem(name: "types", value: "albums"), URLQueryItem(name: "limit", value: "10"),
            ])
        return CatalogAlbums.matchingIDs(found, album: title, artist: artist).first
    }

    func findArtist(name: String) async throws -> String? {
        let found = try await request(
            path: "search",
            query: [
                URLQueryItem(name: "term", value: String(name.prefix(200))),
                URLQueryItem(name: "types", value: "artists"), URLQueryItem(name: "limit", value: "5"),
            ])
        return BrowseCatalogParsing.artistID(found, name: name)
    }

    private static let noSuchItem = CadenzaError.failure("not_found", "Apple's catalog has no such item.")

    private func view(_ name: String, of id: String, limit: Int, if more: Set<String>) async throws -> Data? {
        guard more.contains(name) else { return nil }
        return try await request(
            path: "artists/\(id)/view/\(name)", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    // The views of an artist page that continue past their first page.
    private static func moreViews(_ data: Data) -> Set<String> {
        let artist = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [[String: Any]])?
            .first
        let views = artist?["views"] as? [String: Any] ?? [:]
        return Set(views.compactMap { key, value in (value as? [String: Any])?["next"] != nil ? key : nil })
    }
}
