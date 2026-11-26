import Foundation
import Testing

@testable import CadenzaHost

struct RoomBlendTests {
    private func profile(_ affinities: [String: Double], negative: [String: Double] = [:]) -> RecommendationProfile {
        RecommendationProfile(
            remoteId: UUID().uuidString.lowercased(), passportSequence: 1, expiresAtMs: 0, affinities: affinities,
            transitions: [], negativePreferences: negative, recent: [], noveltyBudget: 0, sessionIntent: nil,
            provenance: [:])
    }

    @Test func aBlendNeedsEveryRemoteToLikeTheArtistAndIsTheirHarmonicMean() throws {
        let both = [profile(["artist-a": 0.8]), profile(["artist-a": 0.2])]
        let score = try #require(RoomBlend.score(artist: "artist-a", profiles: both))

        #expect(abs(score - 0.32) < 0.0001)
        #expect(RoomBlend.score(artist: "artist-a", profiles: [profile(["artist-a": 0.8]), profile([:])]) == nil)
        #expect(RoomBlend.score(artist: "artist-a", profiles: [profile(["artist-a": 0.8])]) == nil)
    }

    @Test func aStrongDislikeFromOneRemoteRemovesTheArtistEvenWhenTheOthersLikeIt() {
        let vetoed = [
            profile(["artist-a": 0.9]),
            profile(["artist-a": 0.9], negative: ["artist-a": -0.8]),
        ]

        #expect(RoomBlend.score(artist: "artist-a", profiles: vetoed) == nil)
        #expect(RoomBlend.isVetoed(artist: "artist-a", profiles: vetoed))
    }

    @Test func aRemoteWithNoOpinionOfAnArtistDoesNotVetoIt() {
        let room = [profile(["artist-a": 0.9]), profile([:])]

        #expect(!RoomBlend.isVetoed(artist: "artist-a", profiles: room))
    }

    @Test func reasonTagsOnlyNameWhatTheProfileSupports() {
        let loved = profile(["artist-a": 0.7])
        let found = profile(["artist-b": 0.3])

        #expect(
            RecommendationReason.tags(artist: "artist-a", profile: loved, inRoomBlend: false, matchesTimeOfDay: false)
                == ["more_from_artist"])
        #expect(
            RecommendationReason.tags(artist: "artist-b", profile: found, inRoomBlend: false, matchesTimeOfDay: false)
                == ["rediscovery"])
        #expect(
            RecommendationReason.tags(artist: "artist-c", profile: loved, inRoomBlend: true, matchesTimeOfDay: true)
                == ["room_blend", "matches_time_of_day"])
        #expect(
            RecommendationReason.tags(artist: "artist-c", profile: loved, inRoomBlend: false, matchesTimeOfDay: false)
                .isEmpty)
    }
}
