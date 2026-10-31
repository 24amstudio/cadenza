import Foundation

struct AnimatedArtworkSource: Sendable, Equatable {
    let albumId: String
    let masterURL: String
}

extension Catalog {
    /// Apple attaches motion artwork to albums. Only an album whose name and artist both match is used, so a similar
    /// release never supplies another album's video.
    func animatedArtwork(album: String, artist: String) async throws -> AnimatedArtworkSource? {
        let found = try await request(
            path: "search",
            query: [
                URLQueryItem(name: "term", value: String("\(album) \(artist)".prefix(200))),
                URLQueryItem(name: "types", value: "albums"), URLQueryItem(name: "limit", value: "10"),
            ])
        for albumId in CatalogAlbums.matchingIDs(found, album: album, artist: artist).prefix(2) {
            let detail = try await request(
                path: "albums/\(albumId)", query: [URLQueryItem(name: "extend", value: "editorialVideo")])
            if let masterURL = CatalogAlbums.motionMaster(detail) {
                return AnimatedArtworkSource(albumId: albumId, masterURL: masterURL)
            }
        }
        return nil
    }
}

enum CatalogAlbums {
    static func matchingIDs(_ data: Data, album: String, artist: String) -> [String] {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let albums = (root?["results"] as? [String: Any])?["albums"] as? [String: Any]
        return (albums?["data"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String, id.range(of: "^[0-9]{1,20}$", options: .regularExpression) != nil,
                let attributes = item["attributes"] as? [String: Any],
                (attributes["name"] as? String)?.compare(album, options: .caseInsensitive) == .orderedSame,
                (attributes["artistName"] as? String)?.compare(artist, options: .caseInsensitive) == .orderedSame
            else { return nil }
            return id
        }
    }

    static func motionMaster(_ data: Data) -> String? {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let attributes = (root?["data"] as? [[String: Any]])?.first?["attributes"] as? [String: Any]
        let video = attributes?["editorialVideo"] as? [String: Any]
        return (video?["motionDetailSquare"] as? [String: Any])?["video"] as? String
    }
}
