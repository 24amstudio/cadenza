import Foundation

actor Catalog {
    var storefront = "us"
    private var token: String?
    private var tokenExpiry: TimeInterval = 0
    private var songs: [SongIdentity: Song] = [:]
    private let http = AppleHTTP()

    func configure(storefront: String) {
        if storefront.range(of: "^[a-z]{2}$", options: .regularExpression) != nil {
            self.storefront = storefront
        }
    }

    func search(_ query: String) async throws -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else { return [] }
        let data = try await request(
            path: "search",
            query: [
                URLQueryItem(name: "term", value: trimmed), URLQueryItem(name: "types", value: "songs"),
                URLQueryItem(name: "limit", value: "40"),
            ])
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = root?["results"] as? [String: Any]
        let songResults = results?["songs"] as? [String: Any]
        return remember(parse(songResults?["data"] as? [[String: Any]] ?? []))
    }

    func resolve(_ identity: SongIdentity) async throws -> Song {
        if let known = songs[identity] { return known }
        guard identity.source == "catalog", Wire.validate(identity) else {
            throw CadenzaError.failure("invalid_command", "The song is not a catalog item.")
        }
        let data = try await request(path: "songs/\(identity.id)", query: [])
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let song = remember(parse(root?["data"] as? [[String: Any]] ?? [])).first else {
            throw CadenzaError.failure("missing_request", "This song is unavailable in the selected storefront.")
        }
        return song
    }

    private func remember(_ found: [Song]) -> [Song] {
        if songs.count > 1_000 { songs.removeAll(keepingCapacity: true) }
        for song in found { songs[song.identity] = song }
        return found
    }

    private func parse(_ items: [[String: Any]]) -> [Song] {
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
                artworkUrl: safeArtwork(image), url: attributes["url"] as? String
            )
        }
    }

    private func safeArtwork(_ value: String?) -> String? {
        guard let value, let url = URL(string: value), url.scheme == "https",
            let host = url.host, host.hasSuffix(".mzstatic.com")
        else { return nil }
        return value
    }

    private func request(path: String, query: [URLQueryItem], retry: Bool = true) async throws -> Data {
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
            try? SecureStore.delete("catalog.public-token")
            return try await self.request(path: path, query: query, retry: false)
        }
        guard response.statusCode == 200 else {
            throw CadenzaError.failure(
                "catalog_unavailable", "Apple's catalog returned HTTP \(response.statusCode). Try again later.")
        }
        return data
    }

    private func developerToken() async throws -> String {
        if let token, tokenExpiry > Date().timeIntervalSince1970 + 300 { return token }
        if let cached = try SecureStore.read("catalog.public-token"),
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
                try SecureStore.write("catalog.public-token", Data(value.utf8))
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
