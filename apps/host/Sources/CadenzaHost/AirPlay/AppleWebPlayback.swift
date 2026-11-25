import Foundation

struct ApplePlaybackAsset: Equatable, Sendable {
    let flavor: String
    let hlsURL: URL
    let licenseServerURL: URL?
    let certURL: URL?
}

/// Resolves Apple webPlayback stream metadata when the user configures a `media-user-token` in Host credentials.
/// Host never downloads or decrypts DRM segments; it only inspects asset URLs for AirPlay FairPlay HLS playlist
/// injection or Cast Widevine license forwarding.
enum AppleWebPlayback {
    static let tokenAccount = "apple.media-user-token"
    private static let endpoint = URL(string: "https://play.itunes.apple.com/WebObjects/MZPlay.woa/wa/webPlayback")!

    static func requestBody(adamId: String) throws -> Data {
        guard adamId.range(of: "^[0-9]{1,20}$", options: .regularExpression) != nil else {
            throw CadenzaError.failure("invalid_command", "Invalid Apple Music catalog identifier.")
        }
        return try JSONSerialization.data(withJSONObject: ["salableAdamId": adamId], options: [.sortedKeys])
    }

    static func parseAssets(from data: Data) -> [ApplePlaybackAsset] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let songList = root["songList"] as? [[String: Any]],
            let first = songList.first,
            let assets = first["assets"] as? [[String: Any]]
        else { return [] }

        return assets.compactMap { asset in
            guard let flavor = asset["flavor"] as? String,
                let rawURL = asset["URL"] as? String,
                let url = safeHTTPSURL(rawURL)
            else { return nil }
            let licenseRaw = (asset["widevine-license-url"] as? String) ?? (asset["license-url"] as? String)
            let certRaw = asset["widevine-cert-url"] as? String
            return ApplePlaybackAsset(
                flavor: flavor,
                hlsURL: url,
                licenseServerURL: licenseRaw.flatMap(safeHTTPSURL),
                certURL: certRaw.flatMap(safeHTTPSURL))
        }
    }

    static func fetchAssets(
        adamId: String,
        developerToken: String,
        mediaUserToken: String,
        http: AppleHTTP = AppleHTTP()
    ) async throws -> [ApplePlaybackAsset] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.httpBody = try requestBody(adamId: adamId)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(developerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(mediaUserToken, forHTTPHeaderField: "Media-User-Token")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        let (data, response) = try await http.data(request, maximum: 524_288)
        guard response.statusCode == 200 else {
            throw CadenzaError.failure(
                "playback_unavailable", "Apple web playback returned HTTP \(response.statusCode).")
        }
        return parseAssets(from: data)
    }

    static func safeHTTPSURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host,
            host.hasSuffix(".apple.com") || host.hasSuffix(".mzstatic.com")
        else { return nil }
        return url
    }
}
