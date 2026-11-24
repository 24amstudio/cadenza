import Foundation

/// Scores a candidate for a room with several connected Remotes. An artist scores only when every Remote has a positive
/// affinity for it, and the blend is their harmonic mean, so one lukewarm Remote pulls the score down. A Remote with a
/// strong negative preference removes the artist from the blend.
enum RoomBlend {
    static let vetoLevel = -0.5

    /// Whether any connected Remote strongly dislikes the artist, which removes it from the room's suggestions.
    static func isVetoed(artist key: String, profiles: [RecommendationProfile]) -> Bool {
        profiles.contains { ($0.negativePreferences[key] ?? 0) <= vetoLevel }
    }

    static func score(artist key: String, profiles: [RecommendationProfile]) -> Double? {
        guard profiles.count >= 2, !isVetoed(artist: key, profiles: profiles) else { return nil }
        var affinities: [Double] = []

        for profile in profiles {
            let affinity = profile.affinities[key] ?? 0
            guard affinity > 0 else { return nil }
            affinities.append(affinity)
        }

        return Double(affinities.count) / affinities.reduce(0) { $0 + 1 / $1 }
    }

    /// Arranges one Remote's ranked candidates for the room. Alone, the ranking stands. With others connected, an artist any
    /// Remote dislikes is dropped, artists every Remote likes come first in blended order, and the rest keep their ranked
    /// order. Every candidate gets the reason tags its data supports.
    static func arrange(
        _ ranked: [RecommendationCandidate], room: [RecommendationProfile], actor: RecommendationProfile,
        timeArtists: Set<String>
    ) -> [RecommendationCandidate] {
        let inRoom = room.count > 1
        var shared: [RecommendationCandidate] = []
        var solo: [RecommendationCandidate] = []

        for candidate in ranked {
            let artist = candidate.track.artistId ?? candidate.song.artist
            if inRoom, isVetoed(artist: artist, profiles: room) { continue }
            var updated = candidate
            let blended = inRoom ? score(artist: artist, profiles: room) : nil
            updated.evidence += RecommendationReason.tags(
                artist: artist, profile: actor, inRoomBlend: blended != nil,
                matchesTimeOfDay: timeArtists.contains(artist))
            if let blended {
                updated.score = blended
                shared.append(updated)
            } else {
                solo.append(updated)
            }
        }

        return shared.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score } + solo
    }
}

/// Explains why a candidate is suggested, using tags the Remote can show. Only tags the data supports are returned.
enum RecommendationReason {
    static let moreFromArtistAffinity = 0.5
    static let rediscoveryAffinity = 0.2

    static func tags(
        artist key: String, profile: RecommendationProfile, inRoomBlend: Bool, matchesTimeOfDay: Bool
    ) -> [String] {
        var tags: [String] = []
        let affinity = profile.affinities[key] ?? 0
        let recentArtists = Set(profile.recent.compactMap(\.artistId))
        let recent = recentArtists.contains(key)

        if !recent, affinity >= moreFromArtistAffinity { tags.append("more_from_artist") }
        if !recent, affinity >= rediscoveryAffinity, affinity < moreFromArtistAffinity { tags.append("rediscovery") }
        if inRoomBlend { tags.append("room_blend") }
        if matchesTimeOfDay { tags.append("matches_time_of_day") }

        return tags
    }
}
