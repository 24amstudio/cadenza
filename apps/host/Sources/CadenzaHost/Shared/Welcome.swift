import Foundation

struct Welcome: Codable, Sendable {
    var hostId: String
    var hostName: String
    var hostEpoch: String
    var remoteId: String
    var token: String? = nil
    var hostAddress: String? = nil
    var hostPort: Int? = nil
    // The Cadenza Web socket's port on hostAddress. It is present only while the Host runs that listener.
    var webPort: Int? = nil
    // The Mac's Bonjour name, which a browser resolves to the current address. Present only with the web listener.
    var webHost: String? = nil
    var hostTimeMs: Int64
    var protocolMajor: Int = 1
    var protocolMinor: Int = 1
    // The Host's version and build, so a Remote can tell whether it or the Host is the older one.
    var hostVersion: String? = nil
    var hostBuild: Int64? = nil
    var platform: String = "macos"
    // The Mac's hardware address, so a Remote can send a Wake-on-LAN packet when the Host is asleep.
    var macAddress: String? = nil
    // The Remote build this Host can offer over the LAN, when a matching release is cached.
    var updateManifest: RemoteUpdateCache.Offer? = nil
    var updates: UpdateConfiguration
    var capabilities: [String] = [
        "playback", "library", "catalog.public-web", "queue.native-accessibility",
        "lyrics.music-cache", "lyrics.english-translation", "analytics", "updates.signed", "queue.play-next",
        "lyrics.lrclib", "artwork.host-cache", "motion.host-cache", "search.suggest", "remote.configure",
        "state.heartbeat", "recommendations.cree",
        "host.update", "library.browse", "playback.modes",
    ]
}
