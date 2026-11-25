import Foundation

struct AnimatedArtistSource: Sendable, Equatable {
    let artistId: String
    let masterURL: String
}

extension Catalog {
    /// Apple attaches motion artwork to artists. Only an artist whose name matches exactly is used, so a similar artist
    /// never supplies another artist's video.
    func animatedArtist(name: String) async throws -> AnimatedArtistSource? {
        let found = try await request(
            path: "search",
            query: [
                URLQueryItem(name: "term", value: String(name.prefix(200))),
                URLQueryItem(name: "types", value: "artists"), URLQueryItem(name: "limit", value: "5"),
            ])
        guard let artistId = CatalogArtists.matchingID(found, name: name) else { return nil }
        let detail = try await request(
            path: "artists/\(artistId)", query: [URLQueryItem(name: "extend", value: "editorialVideo")])
        guard let masterURL = CatalogArtists.motionMaster(detail) else { return nil }
        return AnimatedArtistSource(artistId: artistId, masterURL: masterURL)
    }
}

enum CatalogArtists {
    static func matchingID(_ data: Data, name: String) -> String? {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let artists = (root?["results"] as? [String: Any])?["artists"] as? [String: Any]
        return (artists?["data"] as? [[String: Any]] ?? []).compactMap { item -> String? in
            guard let id = item["id"] as? String, id.range(of: "^[0-9]{1,20}$", options: .regularExpression) != nil,
                let attributes = item["attributes"] as? [String: Any],
                (attributes["name"] as? String)?.compare(name, options: .caseInsensitive) == .orderedSame
            else { return nil }
            return id
        }.first
    }

    // The wide artist rendition is preferred, and the square one is used when Apple has no wide video.
    static func motionMaster(_ data: Data) -> String? {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let attributes = (root?["data"] as? [[String: Any]])?.first?["attributes"] as? [String: Any]
        let video = attributes?["editorialVideo"] as? [String: Any]
        let motion =
            (video?["motionArtistWide"] as? [String: Any]) ?? (video?["motionDetailSquare"] as? [String: Any])
        return motion?["video"] as? String
    }
}
