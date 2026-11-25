import Foundation

/// Chooses how a Google Cast display renders music videos and karaoke visuals: Widevine HLS when a web token is
/// configured, byte-range local `.mp4`/`.m4v` files when DRM-free on disk, or Karaoke Theater Mode fallback.
enum CastVideoRoute: Equatable, Sendable {
    case widevineHLS(hlsURL: URL, licenseURL: URL?, certURL: URL?, mediaUserToken: String, developerToken: String)
    case localVideo(fileURL: URL)
    case theater(artworkURL: URL?, motionURL: URL?)
}

enum CastVideoSource {
    static func resolve(
        song: Song,
        catalog: Catalog,
        music: MusicBridge,
        credentials: CredentialFile,
        lanHost: String,
        streamPort: UInt16,
        hasArtwork: Bool,
        hasMotion: Bool
    ) async -> CastVideoRoute {
        if song.source == "catalog",
            let tokenData = try? credentials.read(AppleWebPlayback.tokenAccount),
            let token = String(data: tokenData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty,
            let devToken = try? await catalog.currentDeveloperToken(),
            let assets = try? await AppleWebPlayback.fetchAssets(
                adamId: song.id, developerToken: devToken, mediaUserToken: token),
            let widevine = assets.first(where: { $0.flavor.lowercased().contains("widevine") })
        {
            return .widevineHLS(
                hlsURL: widevine.hlsURL,
                licenseURL: widevine.licenseServerURL,
                certURL: widevine.certURL,
                mediaUserToken: token,
                developerToken: devToken)
        }

        if song.source == "library", let localURL = await music.videoFileURL(for: song.identity) {
            return .localVideo(fileURL: localURL)
        }

        let artworkURL = hasArtwork ? URL(string: "http://\(lanHost):\(streamPort)/cast/artwork") : nil
        let motionURL = hasMotion ? URL(string: "http://\(lanHost):\(streamPort)/cast/motion.mp4") : nil
        return .theater(artworkURL: artworkURL, motionURL: motionURL)
    }
}
