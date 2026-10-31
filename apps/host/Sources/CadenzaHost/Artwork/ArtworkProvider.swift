import Foundation
import ImageIO

@MainActor
final class ArtworkProvider {
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
        guard let image = CGImageSourceCreateWithData(source as CFData, nil),
            let scaled = CGImageSourceCreateThumbnailAtIndex(
                image, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 600,
                ] as CFDictionary)
        else { throw CadenzaError.failure("artwork_unavailable", "Music's artwork is not an image.") }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil)
        else { throw CadenzaError.failure("artwork_unavailable", "Music's artwork could not be prepared.") }
        CGImageDestinationAddImage(
            destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CadenzaError.failure("artwork_unavailable", "Music's artwork could not be prepared.")
        }
        let url = Self.localArtworkURL(occurrenceId: occurrenceId)
        try cache.put(encoded as Data, for: "artwork:" + url, kind: "artwork")
        return url
    }
}
