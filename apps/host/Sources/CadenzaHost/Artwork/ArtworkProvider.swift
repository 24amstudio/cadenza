import Foundation
import ImageIO

@MainActor
final class ArtworkProvider {
    private var previews: [String: String] = [:]
    // Music supplies artwork for the track it plays, including streams with no catalog match. That artwork has no
    // catalog address, so it is stored in the cache under this scheme and is never fetched from the network.
    nonisolated static let musicScheme = "cadenza-music-artwork://"

    private let cache: HostCache
    private let http = ArtworkHTTP()
    private let maximumBytes = 524_288

    init(cache: HostCache) { self.cache = cache }

    nonisolated static func isAllowedURL(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil,
            let host = url.host?.lowercased(), host.hasSuffix(".mzstatic.com"), host != "mzstatic.com"
        else { return false }
        return value.utf8.count <= 2_048
    }

    nonisolated static func localArtworkURL(occurrenceId: String) -> String {
        musicScheme + occurrenceId
    }

    nonisolated static func isLocalArtworkURL(_ value: String) -> Bool {
        guard value.hasPrefix(musicScheme) else { return false }
        return UUID(uuidString: String(value.dropFirst(musicScheme.count))) != nil
    }

    nonisolated static func isServableURL(_ value: String) -> Bool {
        isAllowedURL(value) || isLocalArtworkURL(value)
    }

    func data(for url: String) async throws -> Data? {
        if Self.isLocalArtworkURL(url) {
            guard let cached = try cache.data(for: "artwork:" + url) else {
                throw CadenzaError.failure("artwork_unavailable", "This song's artwork is no longer in the Host cache.")
            }
            return cached
        }
        guard Self.isAllowedURL(url) else {
            throw CadenzaError.failure("artwork_unavailable", "The artwork address is not an Apple CDN URL.")
        }
        if let cached = try cache.data(for: "artwork:" + url) { return cached }
        let fetched = try await http.data(URLRequest(url: URL(string: url)!), maximum: maximumBytes)
        guard let source = CGImageSourceCreateWithData(fetched.0 as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
            (1...2_048).contains(width.intValue), (1...2_048).contains(height.intValue)
        else { throw CadenzaError.failure("artwork_unavailable", "The artwork response was not an image.") }
        try cache.put(fetched.0, for: "artwork:" + url, kind: "artwork")
        return fetched.0
    }

    // Scales Music's artwork to a JPEG well inside the transfer limit, then stores it under the playing occurrence.
    func storeMusicArtwork(_ source: Data, occurrenceId: String) throws -> String {
        let encoded = try Self.jpeg(source, maxPixelSize: 600, quality: 0.85)
        let url = Self.localArtworkURL(occurrenceId: occurrenceId)
        try cache.put(encoded, for: "artwork:" + url, kind: "artwork")
        return url
    }

    // A small JPEG of the cover. A browser on Bluetooth shows it while the full image is still crossing the link.
    // The small cover, at most 32 by 32 pixels, that a song's state carries.
    nonisolated static func preview(of source: Data) throws -> Data {
        try jpeg(source, maxPixelSize: 32, quality: 0.7)
    }

    func cachedPreview(for url: String) -> String? { previews[url] }

    // Fetches the cover once and keeps its preview. Nil when the cover cannot be fetched or decoded.
    func preview(for url: String) async -> String? {
        if let cached = previews[url] { return cached }
        guard let source = try? await self.data(for: url), let small = try? Self.preview(of: source) else { return nil }
        if previews.count >= 64 { previews.removeAll() }
        previews[url] = small.base64EncodedString()
        return previews[url]
    }

    // Album art travels at most 256 by 256 pixels, so a Bluetooth link carries a small image. A smaller image is sent as it is.
    nonisolated static let albumArtSide = 256

    nonisolated static func fullSize(of source: Data) throws -> Data {
        guard let image = CGImageSourceCreateWithData(source as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw CadenzaError.failure("artwork_unavailable", "The artwork is not an image.") }
        guard max(width, height) > albumArtSide else { return source }
        return try jpeg(source, maxPixelSize: albumArtSide, quality: 0.85)
    }

    private nonisolated static func jpeg(_ source: Data, maxPixelSize: Int, quality: Double) throws -> Data {
        guard let image = CGImageSourceCreateWithData(source as CFData, nil),
            let scaled = CGImageSourceCreateThumbnailAtIndex(
                image, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                ] as CFDictionary)
        else { throw CadenzaError.failure("artwork_unavailable", "The artwork is not an image.") }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil)
        else { throw CadenzaError.failure("artwork_unavailable", "The artwork could not be prepared.") }
        CGImageDestinationAddImage(
            destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CadenzaError.failure("artwork_unavailable", "The artwork could not be prepared.")
        }
        return encoded as Data
    }
}
