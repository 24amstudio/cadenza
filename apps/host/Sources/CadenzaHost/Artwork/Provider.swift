import Foundation
import ImageIO

@MainActor
final class ArtworkProvider {
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

    func data(for url: String) async throws -> Data? {
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
            width.intValue in 1...2_048, height.intValue in 1...2_048
        else { throw CadenzaError.failure("artwork_unavailable", "The artwork response was not an image.") }
        try cache.put(fetched.0, for: "artwork:" + url, kind: "artwork")
        return fetched.0
    }
}
