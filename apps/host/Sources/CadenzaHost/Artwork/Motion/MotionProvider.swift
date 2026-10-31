import Foundation

// Animated album art is fetched once per album and kept in the Host cache. The Remote receives the same bytes through its
// authenticated session, so it never contacts Apple's motion CDN.
@MainActor
final class MotionProvider {
    private static let playlistLimit = 64 * 1_024
    private static let videoLimit = 8 * 1_048_576
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
        if let albumId = albumIds[key], let cached = try cache.data(for: Self.cacheKey(albumId)) { return cached }
        guard let source = try await catalog.animatedArtwork(album: album, artist: artist) else {
            if withoutMotion.count >= 512 { withoutMotion.removeAll() }
            withoutMotion.insert(key)
            return nil
        }
        if albumIds.count >= 512 { albumIds.removeAll() }
        albumIds[key] = source.albumId
        if let cached = try cache.data(for: Self.cacheKey(source.albumId)) { return cached }
        let video = try await download(source.masterURL)
        try cache.put(video, for: Self.cacheKey(source.albumId), kind: "animated_artwork")
        return video
    }

    private static func cacheKey(_ albumId: String) -> String { "motion:" + albumId }

    private func download(_ master: String) async throws -> Data {
        let unavailable = CadenzaError.failure("motion_unavailable", "Motion artwork is unavailable.")
        guard let masterURL = URL(string: master) else { throw unavailable }
        let master = try await text(masterURL)
        guard let renditionURL = MotionPlaylist.h264Rendition(master, base: masterURL) else { throw unavailable }
        let rendition = try await text(renditionURL)
        guard let fileURL = MotionPlaylist.mediaFile(rendition, base: renditionURL) else { throw unavailable }
        let (video, _) = try await http.data(URLRequest(url: fileURL), maximum: Self.videoLimit)
        guard MotionPlaylist.isMP4(video) else { throw unavailable }
        return video
    }

    private func text(_ url: URL) async throws -> String {
        let (data, _) = try await http.data(URLRequest(url: url), maximum: Self.playlistLimit)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CadenzaError.failure("motion_unavailable", "Motion artwork is unavailable.")
        }
        return text
    }
}
