import Foundation

/// The taste summary a Remote attaches to its hello. A Remote sends one only after the user opts in, so a hello without one
/// means no digest is kept.
struct RemoteTasteDigest: Codable, Equatable, Sendable {
    /// The affinity a digest artist starts with when the Host has no listening history for it.
    static let priorAffinity = 0.3

    var topArtists: [String]
    var topGenres: [String]
    var favoritedTrackIds: [String]

    /// Rejects a digest over the protocol limits before it reaches the store.
    func validated() throws -> RemoteTasteDigest {
        guard
            topArtists.count <= 20, topGenres.count <= 20, favoritedTrackIds.count <= 200,
            topArtists.allSatisfy({ (1...200).contains($0.unicodeScalars.count) }),
            topGenres.allSatisfy({ (1...100).contains($0.unicodeScalars.count) }),
            favoritedTrackIds.allSatisfy({ (1...200).contains($0.unicodeScalars.count) })
        else {
            throw CadenzaError.failure("invalid_command", "The taste digest exceeds the protocol limits.")
        }
        return self
    }

    /// Gives digest artists a prior where the profile has no opinion, so a new pairing is personal before its history builds.
    func seeding(_ profile: RecommendationProfile) -> RecommendationProfile {
        var seeded = profile
        for artist in topArtists where seeded.affinities[artist] == nil && seeded.negativePreferences[artist] == nil {
            seeded.affinities[artist] = Self.priorAffinity
        }
        return seeded
    }
}
