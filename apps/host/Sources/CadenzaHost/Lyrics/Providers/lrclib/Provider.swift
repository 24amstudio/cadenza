import Foundation

struct LRCLIBProvider: LyricsProvider {
    let id = "lrclib"
    private let http = LRCLIBHTTP()

    func document(song: Song, occurrence: String) async throws -> LyricDocument? {
        guard !song.title.isEmpty, !song.artist.isEmpty else { return nil }
        let exact = try await request(path: "get", query: query(song))
        let match = try decode(exact, song: song)
        if let match { return try LRCParser.document(match, occurrence: occurrence) }

        guard let search = try await request(path: "search", query: searchQuery(song)) else { return nil }
        let candidates = try JSONDecoder().decode([LRCLIBRecord].self, from: search).prefix(20)
        for candidate in candidates where candidate.matches(song) {
            if let document = try LRCParser.document(candidate, occurrence: occurrence) { return document }
        }
        return nil
    }

    private func request(path: String, query: [URLQueryItem]) async throws -> Data? {
        var components = URLComponents(string: "https://lrclib.net/api/" + path)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Cadenza Host lyrics provider", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await http.data(request, maximum: 524_288)
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else {
            throw CadenzaError.failure(
                "lyrics_provider", "LRCLIB returned HTTP \(response.statusCode) while looking up lyrics.")
        }
        return data
    }

    private func decode(_ data: Data?, song: Song) throws -> LRCLIBRecord? {
        guard let data else { return nil }
        let record = try JSONDecoder().decode(LRCLIBRecord.self, from: data)
        guard record.matches(song) else { return nil }
        return record
    }

    private func query(_ song: Song) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "track_name", value: song.title),
            URLQueryItem(name: "artist_name", value: song.artist),
        ]
        if !song.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: song.album)) }
        if let duration = song.durationMs { items.append(URLQueryItem(name: "duration", value: String(duration / 1_000))) }
        return items
    }

    private func searchQuery(_ song: Song) -> [URLQueryItem] {
        query(song) + [URLQueryItem(name: "q", value: song.title)]
    }
}
