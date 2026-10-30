import Foundation

struct Welcome: Codable, Sendable {
    var hostId: String
    var hostName: String
    var hostEpoch: String
    var remoteId: String
    var token: String? = nil
    var hostTimeMs: Int64
    var protocolMajor: Int = 1
    var protocolMinor: Int = 1
    var updates: UpdateConfiguration
    var capabilities: [String] = [
        "playback", "library", "catalog.public-web", "queue.native-accessibility",
        "lyrics.music-cache", "lyrics.english-translation", "analytics", "updates.signed", "queue.play-next",
        "lyrics.lrclib", "artwork.host-cache", "remote.configure", "state.heartbeat", "recommendations.cree",
    ]
}
