import Foundation

// Animated album art is fetched once per album and kept in the Host cache. The Remote receives the same bytes through its
// authenticated session, so it never contacts Apple's motion CDN.
@MainActor
final class MotionProvider {
    private static let playlistLimit = 64 * 1_024
    // The largest motion video the Host sends. Bigger files are refused, so the Remote keeps its still artwork.
    static let videoLimit = 1_048_576
    // The rendition as Apple sends it, under the bitrate ceiling, before it is rescaled to the album art size.
    private static let sourceLimit = 4 * 1_048_576
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
        let video = try await download(source.masterURL)
        try cache.put(video, for: Self.cacheKey(source.albumId), kind: "animated_artwork")
        return video
    }

    // The key names the rescaled video, so a video cached before rescaling is never served.
    private static func cacheKey(_ albumId: String) -> String { "motion256:" + albumId }

    // A video cached before the size limit is downloaded again, so the cap holds for every video the Host sends.
    private func cachedVideo(_ albumId: String) throws -> Data? {
        guard let data = try cache.data(for: Self.cacheKey(albumId)), data.count <= Self.videoLimit else { return nil }
        return data
    }

    private func download(_ master: String) async throws -> Data {
        let unavailable = CadenzaError.failure("motion_unavailable", "Motion artwork is unavailable.")
        guard let masterURL = URL(string: master) else { throw unavailable }
        let master = try await text(masterURL)
        guard let renditionURL = MotionPlaylist.h264Rendition(master, base: masterURL) else { throw unavailable }
        let rendition = try await text(renditionURL)
        guard let fileURL = MotionPlaylist.mediaFile(rendition, base: renditionURL) else { throw unavailable }
        let (source, _) = try await http.data(URLRequest(url: fileURL), maximum: Self.sourceLimit)
        guard MotionPlaylist.isMP4(source) else { throw unavailable }
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
