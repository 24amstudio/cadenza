import Foundation

/// Turns Apple's catalog JSON into browse results. Everything here is pure, so it can be checked without a network.
enum BrowseCatalogParsing {
    private typealias JSON = [String: Any]

    static func artist(main: Data, topSongs: Data? = nil, albums: Data? = nil) -> BrowseResult? {
        guard let artist = firstResource(main), let id = artist["id"] as? String, validID(id),
            let attributes = artist["attributes"] as? JSON, let name = attributes["name"] as? String
        else { return nil }
        let views = artist["views"] as? JSON ?? [:]
        func view(_ key: String, replacement: Data?) -> [JSON] {
            if let replacement, let items = firstItems(replacement) { return items }
            return ((views[key] as? JSON)?["data"] as? [JSON]) ?? []
        }
        let genres = genreNames(attributes)
        var sections: [BrowseSection] = []
        let songs = Catalog.parseSongs(
            view("top-songs", replacement: topSongs).filter { $0["type"] as? String == "songs" })
        if !songs.isEmpty {
            sections.append(BrowseSection(id: "top_songs", title: "Top Songs", items: songs.map(BrowseItem.song)))
        }
        let full = albumItems(view("full-albums", replacement: albums))
        if !full.isEmpty { sections.append(BrowseSection(id: "albums", title: "Albums", items: full)) }
        let singles = albumItems(view("singles", replacement: nil))
        if !singles.isEmpty { sections.append(BrowseSection(id: "singles", title: "Singles & EPs", items: singles)) }
        return BrowseResult(
            kind: "artist", id: id, title: name, subtitle: genres.first, artworkUrl: artwork(attributes),
            detail: biography(attributes) ?? (genres.isEmpty ? nil : genres.joined(separator: " · ")),
            sections: sections)
    }

    static func album(_ data: Data) -> BrowseResult? {
        guard let album = firstResource(data), let id = album["id"] as? String, validID(id),
            let attributes = album["attributes"] as? JSON, let name = attributes["name"] as? String
        else { return nil }
        let tracks = ((album["relationships"] as? JSON)?["tracks"] as? JSON)?["data"] as? [JSON] ?? []
        let songs = Catalog.parseSongs(tracks.filter { $0["type"] as? String == "songs" })
        var facts: [String] = []
        if let year = year(attributes) { facts.append(year) }
        if let genre = genreNames(attributes).first { facts.append(genre) }
        if let count = songs.isEmpty ? nil : songs.count { facts.append(count == 1 ? "1 song" : "\(count) songs") }
        return BrowseResult(
            kind: "album", id: id, title: name, subtitle: attributes["artistName"] as? String,
            artworkUrl: artwork(attributes), detail: facts.isEmpty ? nil : facts.joined(separator: " · "),
            sections: songs.isEmpty
                ? [] : [BrowseSection(id: "songs", title: "Songs", items: songs.map(BrowseItem.song))])
    }

    /// The album and first artist of a song fetched with `include=albums,artists`.
    static func relations(_ data: Data) -> (album: String?, artist: String?) {
        let relationships = firstResource(data)?["relationships"] as? JSON
        func first(_ key: String) -> String? {
            let id = ((relationships?[key] as? JSON)?["data"] as? [JSON])?.first?["id"] as? String
            return id.flatMap { validID($0) ? $0 : nil }
        }
        return (first("albums"), first("artists"))
    }

    /// The first search hit of a kind (`artists`) whose name matches exactly, ignoring case.
    static func artistID(_ data: Data, name: String) -> String? {
        let root = try? JSONSerialization.jsonObject(with: data) as? JSON
        let artists = (root?["results"] as? JSON)?["artists"] as? JSON
        return (artists?["data"] as? [JSON] ?? []).lazy.compactMap { item -> String? in
            guard let id = item["id"] as? String, validID(id),
                (item["attributes"] as? JSON)?["name"] as? String != nil,
                ((item["attributes"] as? JSON)?["name"] as? String)?.compare(name, options: .caseInsensitive)
                    == .orderedSame
            else { return nil }
            return id
        }.first
    }

    private static func albumItems(_ items: [JSON]) -> [BrowseItem] {
        items.compactMap { item in
            guard item["type"] as? String == "albums", let id = item["id"] as? String, validID(id),
                let attributes = item["attributes"] as? JSON, let name = attributes["name"] as? String
            else { return nil }
            var facts: [String] = []
            if let year = year(attributes) { facts.append(year) }
            if attributes["isSingle"] as? Bool == true {
                facts.append("Single")
            } else if let count = (attributes["trackCount"] as? NSNumber)?.intValue, count > 0 {
                facts.append(count == 1 ? "1 song" : "\(count) songs")
            }
            return BrowseItem(
                type: "album", id: id, title: name, subtitle: facts.isEmpty ? nil : facts.joined(separator: " · "),
                artworkUrl: artwork(attributes))
        }
    }

    private static func firstResource(_ data: Data) -> JSON? {
        firstItems(data)?.first
    }

    private static func firstItems(_ data: Data) -> [JSON]? {
        (try? JSONSerialization.jsonObject(with: data) as? JSON)?["data"] as? [JSON]
    }

    private static func validID(_ id: String) -> Bool {
        id.range(of: "^[1-9][0-9]{0,19}$", options: .regularExpression) != nil
    }

    private static func genreNames(_ attributes: JSON) -> [String] {
        (attributes["genreNames"] as? [String] ?? []).filter { $0 != "Music" && !$0.isEmpty }
    }

    private static func year(_ attributes: JSON) -> String? {
        guard let date = attributes["releaseDate"] as? String, date.count >= 4 else { return nil }
        let year = String(date.prefix(4))
        return year.allSatisfy(\.isNumber) ? year : nil
    }

    /// Artwork at the size search results use, so the Host's artwork cache serves both from one entry.
    static func artwork(_ attributes: [String: Any]) -> String? {
        let url = ((attributes["artwork"] as? JSON)?["url"] as? String)?
            .replacingOccurrences(of: "{w}", with: "400").replacingOccurrences(of: "{h}", with: "400")
            .replacingOccurrences(of: "{c}", with: "bb").replacingOccurrences(of: "{f}", with: "jpg")
        return Catalog.safeArtwork(url)
    }

    private static func biography(_ attributes: JSON) -> String? {
        let notes = attributes["editorialNotes"] as? JSON
        let raw =
            (attributes["artistBio"] as? String) ?? (notes?["short"] as? String) ?? (notes?["standard"] as? String)
        guard let raw else { return nil }
        // Paragraph breaks separate words; inline tags such as <b> do not.
        let plain = raw.replacingOccurrences(of: "</?(p|br)[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !plain.isEmpty else { return nil }
        guard plain.count > 480 else { return plain }
        let cut = plain.prefix(480)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }
}
