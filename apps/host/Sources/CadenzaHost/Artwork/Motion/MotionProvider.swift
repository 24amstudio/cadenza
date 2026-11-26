import Foundation

// Animated album and artist art is fetched once and kept in the Host cache. The Remote receives the same bytes through
// its authenticated session, so it never contacts Apple's motion CDN.
@MainActor
final class MotionProvider {
    private static let playlistLimit = 64 * 1_024
    // The largest motion video the Host sends. Bigger files are refused, so the Remote keeps its still artwork.
    static let videoLimit = 1_048_576
    // The rendition as Apple sends it, under the bitrate ceiling, before optional rescaling.
    private static let sourceLimit = 4 * 1_048_576
    // Artist editorialVideo .m3u8 URLs are cached in Host SQLite for 7 days.
    static let artistURLTTLMs: Int64 = 7 * 24 * 60 * 60 * 1_000

    private struct CachedArtistURL: Codable {
        let artistId: String
        let masterURL: String
        let cachedAtMs: Int64
    }

    private let catalog: Catalog
    private let cache: HostCache
    private let http = AppleHTTP()
    private var albumIds: [String: String] = [:]
    private var withoutMotion: Set<String> = []

    init(catalog: Catalog, cache: HostCache) {
        self.catalog = catalog
        self.cache = cache
    }

    /// The album's motion video, or nil when Apple has none for it. Lookup failures throw instead of being remembered.
    func video(album: String, artist: String) async throws -> Data? {
        let key = (album + "\u{1F}" + artist).lowercased()
        guard !album.isEmpty, !withoutMotion.contains(key) else { return nil }
        if let albumId = albumIds[key], let cached = try cachedVideo(albumId) { return cached }
        guard let source = try await catalog.animatedArtwork(album: album, artist: artist) else {
            if withoutMotion.count >= 512 { withoutMotion.removeAll() }
            withoutMotion.insert(key)
            return nil
        }
        if albumIds.count >= 512 { albumIds.removeAll() }
        albumIds[key] = source.albumId
        if let cached = try cachedVideo(source.albumId) { return cached }
        let video = try await download(source.masterURL, transcodeToSquare: true)
        try cache.put(video, for: Self.cacheKey(source.albumId), kind: "animated_artwork")
        return video
    }

    /// The artist's motion video, or nil when Apple has none for that artist. Resolves editorialVideo URLs in a
    /// detached .utility task, caches the URL in Host SQLite with a 7-day TTL, and serves bounded H.264 MP4s without
    /// transcoding when they already fit the size limit.
    func artistVideo(name: String) async throws -> Data? {
        // The record separator keeps artist keys apart from album keys, which also hold an artist name.
        let key = "\u{1E}artist\u{1F}" + name.lowercased()
        guard !withoutMotion.contains(key) else { return nil }
        guard let source = try await resolveArtistSource(name: name) else {
            if withoutMotion.count >= 512 { withoutMotion.removeAll() }
            withoutMotion.insert(key)
            return nil
        }
        let cacheKey = "motion-artist:" + source.artistId
        if let cached = try cache.data(for: cacheKey), cached.count <= Self.videoLimit { return cached }
        let video = try await download(source.masterURL, transcodeToSquare: false)
        try cache.put(video, for: cacheKey, kind: "animated_artwork")
        return video
    }

    /// Reads the cached artist editorialVideo URL if younger than 7 days, otherwise resolves it in a .utility task.
    func resolveArtistSource(name: String, nowMs: Int64 = wallMs()) async throws -> AnimatedArtistSource? {
        let urlKey = "artist-motion-url:" + name.lowercased()
        if let data = try cache.data(for: urlKey),
            let entry = try? JSONDecoder().decode(CachedArtistURL.self, from: data),
            nowMs - entry.cachedAtMs < Self.artistURLTTLMs
        {
            return AnimatedArtistSource(artistId: entry.artistId, masterURL: entry.masterURL)
        }
        let catalogRef = self.catalog
        let resolved = try await Task.detached(priority: .utility) {
            try await catalogRef.animatedArtist(name: name)
        }.value
        guard let source = resolved else { return nil }
        let entry = CachedArtistURL(artistId: source.artistId, masterURL: source.masterURL, cachedAtMs: nowMs)
        if let encoded = try? JSONEncoder().encode(entry) {
            try? cache.put(encoded, for: urlKey, kind: "provider")
        }
        return source
    }

    // The key names the rescaled video, so a video cached before rescaling is never served.
    private static func cacheKey(_ albumId: String) -> String { "motion256:" + albumId }

    // A video cached before the size limit is downloaded again, so the cap holds for every video the Host sends.
    private func cachedVideo(_ albumId: String) throws -> Data? {
        guard let data = try cache.data(for: Self.cacheKey(albumId)), data.count <= Self.videoLimit else { return nil }
        return data
    }

    private func download(_ master: String, transcodeToSquare: Bool) async throws -> Data {
        let unavailable = CadenzaError.failure("motion_unavailable", "Motion artwork is unavailable.")
        guard let masterURL = URL(string: master) else { throw unavailable }
        let master = try await text(masterURL)
        guard let renditionURL = MotionPlaylist.h264Rendition(master, base: masterURL) else { throw unavailable }
        let rendition = try await text(renditionURL)
        guard let fileURL = MotionPlaylist.mediaFile(rendition, base: renditionURL) else { throw unavailable }
        let (source, _) = try await http.data(URLRequest(url: fileURL), maximum: Self.sourceLimit)
        guard MotionPlaylist.isMP4(source) else { throw unavailable }
        if !transcodeToSquare && source.count <= Self.videoLimit {
            return source
        }
        // Rescaling runs off the main actor, so the Host's interface and other transfers keep moving while it encodes.
        let scaled = try await Task.detached(priority: .utility) { try await MotionTranscoder.transcode(source) }.value
        guard scaled.count <= Self.videoLimit else { throw unavailable }
        return scaled
    }

    private func text(_ url: URL) async throws -> String {
        let (data, _) = try await http.data(URLRequest(url: url), maximum: Self.playlistLimit)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CadenzaError.failure("motion_unavailable", "Motion artwork is unavailable.")
        }
        return text
    }
}
