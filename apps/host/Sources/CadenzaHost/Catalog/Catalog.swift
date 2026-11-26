import Foundation

actor Catalog {
    var storefront = "us"
    private var token: String?
    private var tokenExpiry: TimeInterval = 0
    private var songs: [SongIdentity: Song] = [:]
    // Music video IDs found by search. Apple's song lookup must not be used for them, because they are not songs.
    private var videos: [String: Song] = [:]
    // Public AAC preview URLs for catalog songs, used by VideoEnvelopeAlignment without storing them in Song wire payloads.
    private var previewURLs: [String: URL] = [:]
    private let http = AppleHTTP()
    private let credentials: CredentialFile

    init(credentials: CredentialFile) {
        self.credentials = credentials
    }

    func configure(storefront: String) {
        if storefront.range(of: "^[a-z]{2}$", options: .regularExpression) != nil {
            self.storefront = storefront
        }
    }

    func search(_ query: String, videos: Bool = false) async throws -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else { return [] }
        let data = try await request(
            path: "search",
            query: [
                URLQueryItem(name: "term", value: trimmed),
                URLQueryItem(name: "types", value: videos ? "songs,music-videos" : "songs"),
                URLQueryItem(name: "limit", value: "40"),
            ])
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = root?["results"] as? [String: Any]
        let songResults = results?["songs"] as? [String: Any]
        let videoResults = results?["music-videos"] as? [String: Any]
        var found = Self.parseSongs(songResults?["data"] as? [[String: Any]] ?? [])
        rememberPreviews(songResults?["data"] as? [[String: Any]] ?? [])
        if videos {
            found += Self.parseSongs(videoResults?["data"] as? [[String: Any]] ?? [], mediaType: .musicVideo)
        }
        return remember(found)
    }

    // Apple's completions for the text being typed: terms to search next, and its top song matches.
    func suggest(_ term: String) async throws -> CatalogSuggestions {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else { return CatalogSuggestions(terms: [], songs: []) }
        let data = try await request(
            path: "search/suggestions",
            query: [
                URLQueryItem(name: "term", value: trimmed), URLQueryItem(name: "kinds", value: "terms,topResults"),
                URLQueryItem(name: "types", value: "songs,artists,albums"), URLQueryItem(name: "limit", value: "8"),
            ])
        let suggestions = CatalogSuggestions.parse(data)
        _ = remember(suggestions.songs)
        return suggestions
    }

    func resolve(_ identity: SongIdentity) async throws -> Song {
        if let known = songs[identity] { return known }
        if identity.source == "catalog", videos[identity.id] != nil {
            throw CadenzaError.failure("unsupported_media", "Music video playback is not available yet.")
        }
        guard identity.source == "catalog", Wire.validate(identity) else {
            throw CadenzaError.failure("invalid_command", "The song is not a catalog item.")
        }
        let data = try await request(path: "songs/\(identity.id)", query: [])
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let song = remember(Self.parseSongs(root?["data"] as? [[String: Any]] ?? [])).first else {
            throw CadenzaError.failure("missing_request", "This song is unavailable in the selected storefront.")
        }
        return song
    }

    // A music video the last search returned. Playback reads its Music link from here.
    func video(id: String) -> Song? { videos[id] }

    /// Public AAC preview URL for a catalog song, fetching the song record if not yet cached.
    func previewURL(for songId: String) async -> URL? {
        if let cached = previewURLs[songId] { return cached }
        guard Wire.validate(SongIdentity(source: "catalog", id: songId)),
            let data = try? await request(path: "songs/\(songId)", query: [])
        else { return nil }
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        rememberPreviews(root?["data"] as? [[String: Any]] ?? [])
        return previewURLs[songId]
    }

    /// Downloads a public AAC preview from Apple's preview CDN (<= 4 MB).
    func previewAudioData(for songId: String) async throws -> Data? {
        guard let url = await previewURL(for: songId) else { return nil }
        let (data, _) = try await http.data(URLRequest(url: url), maximum: AudioEnvelopeDecoder.previewSizeLimit)
        return data
    }

    private func rememberPreviews(_ items: [[String: Any]]) {
        if previewURLs.count > 1_000 { previewURLs.removeAll(keepingCapacity: true) }
        for item in items {
            guard let id = item["id"] as? String,
                let attributes = item["attributes"] as? [String: Any],
                let previews = attributes["previews"] as? [[String: Any]],
                let raw = previews.first?["url"] as? String,
                let url = Self.safePreviewURL(raw)
            else { continue }
            previewURLs[id] = url
        }
    }

    static func safePreviewURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https",
            let host = url.host, host == "audio-ssl.itunes.apple.com" || host.hasSuffix(".itunes.apple.com")
        else { return nil }
        return url
    }

    func remember(_ found: [Song]) -> [Song] {
        if songs.count > 1_000 { songs.removeAll(keepingCapacity: true) }
        if videos.count > 1_000 { videos.removeAll(keepingCapacity: true) }
        for song in found {
            if song.mediaType == .musicVideo {
                videos[song.id] = song
            } else {
                songs[song.identity] = song
            }
        }
        return found
    }

    static func parseSongs(_ items: [[String: Any]], mediaType: MediaType = .song) -> [Song] {
        items.compactMap { item in
            guard let id = item["id"] as? String,
                let attributes = item["attributes"] as? [String: Any],
                let title = attributes["name"] as? String,
                let artist = attributes["artistName"] as? String,
                Wire.validate(SongIdentity(source: "catalog", id: id))
            else { return nil }
            let artwork = attributes["artwork"] as? [String: Any]
            let image = (artwork?["url"] as? String)?
                .replacingOccurrences(of: "{w}", with: "400")
                .replacingOccurrences(of: "{h}", with: "400")
            return Song(
                source: "catalog", id: id, title: String(title.prefix(500)), artist: String(artist.prefix(500)),
                album: String((attributes["albumName"] as? String ?? "").prefix(500)),
                durationMs: (attributes["durationInMillis"] as? NSNumber)?.int64Value,
                artworkUrl: safeArtwork(image), url: attributes["url"] as? String, mediaType: mediaType
            )
        }
    }

    static func safeArtwork(_ value: String?) -> String? {
        guard let value, let url = URL(string: value), url.scheme == "https",
            let host = url.host, host.hasSuffix(".mzstatic.com")
        else { return nil }
        return value
    }

    func request(
        path: String, query: [URLQueryItem], retry: Bool = true, missingIsNotFound: Bool = false
    ) async throws -> Data {
        let credential = try await developerToken()
        var components = URLComponents(string: "https://amp-api.music.apple.com/v1/catalog/\(storefront)/\(path)")!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        let (data, response) = try await http.data(request, maximum: 2_097_152)
        if response.statusCode == 401 && retry {
            token = nil
            tokenExpiry = 0
            try? credentials.delete("catalog.public-token")
            return try await self.request(
                path: path, query: query, retry: false, missingIsNotFound: missingIsNotFound)
        }
        if response.statusCode == 404 && missingIsNotFound {
            throw CadenzaError.failure("not_found", "Apple's catalog has no such item in this storefront.")
        }
        guard response.statusCode == 200 else {
            throw CadenzaError.failure(
                "catalog_unavailable", "Apple's catalog returned HTTP \(response.statusCode). Try again later.")
        }
        return data
    }

    func currentDeveloperToken() async throws -> String {
        try await developerToken()
    }

    private func developerToken() async throws -> String {
        if let token, tokenExpiry > Date().timeIntervalSince1970 + 300 { return token }
        if let cached = try credentials.read("catalog.public-token"),
            let value = String(data: cached, encoding: .utf8),
            let expiry = expiry(value), expiry > Date().timeIntervalSince1970 + 300
        {
            token = value
            tokenExpiry = expiry
            return value
        }
        let request = URLRequest(url: URL(string: "https://music.apple.com/us/browse")!)
        let (html, _) = try await http.data(request, maximum: 4_194_304)
        let text = String(decoding: html, as: UTF8.self)
        let pattern = #"/assets/index[~\-][A-Za-z0-9._\-]+\.js"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        let paths = regex.matches(in: text, range: range).prefix(4).compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
        for path in Set(paths) {
            let request = URLRequest(url: URL(string: "https://music.apple.com\(path)")!)
            let (bundle, _) = try await http.data(request, maximum: 12_582_912)
            if let value = try extractToken(String(decoding: bundle, as: UTF8.self)),
                let expiry = expiry(value)
            {
                token = value
                tokenExpiry = expiry
                try credentials.write("catalog.public-token", Data(value.utf8))
                return value
            }
        }
        throw CadenzaError.failure(
            "catalog_unavailable",
            "Apple's public web catalog integration changed. Local library and playback controls remain available."
        )
    }

    private func extractToken(_ text: String) throws -> String? {
        let regex = try NSRegularExpression(pattern: #"[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}"#)
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let range = Range(match.range, in: text) else { continue }
            let candidate = String(text[range])
            if let expiry = expiry(candidate), expiry > Date().timeIntervalSince1970 + 300 { return candidate }
        }
        return nil
    }

    private func expiry(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["iss"] as? String == "AMPWebPlay"
        else { return nil }
        return (object["exp"] as? NSNumber)?.doubleValue
    }
}

// URLSession uses this immutable delegate to refuse redirects off the fixed Apple origins.
