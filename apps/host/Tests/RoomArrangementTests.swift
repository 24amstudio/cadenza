import Foundation
import Testing

@testable import CadenzaHost

struct RoomArrangementTests {
    private func profile(
        _ remoteId: String, affinities: [String: Double] = [:], negative: [String: Double] = [:]
    ) -> RecommendationProfile {
        RecommendationProfile(
            remoteId: remoteId, passportSequence: 1, expiresAtMs: 0, affinities: affinities, transitions: [],
            negativePreferences: negative, recent: [], noveltyBudget: 0, sessionIntent: nil, provenance: [:])
    }

    private func candidate(_ artist: String, score: Double) -> RecommendationCandidate {
        RecommendationCandidate(
            track: RecommendationTrack(
                source: "catalog", id: "\(artist)-track", artistId: artist, albumId: nil, versionId: nil),
            song: Song(source: "catalog", id: "\(artist)-track", title: "Track", artist: artist),
            source: "cadenza", confidence: 0.5, evidence: [], applePrior: nil, metadataCompleteness: 1,
            availability: true, score: score)
    }

    @Test func aSingleRemoteKeepsItsRankingAndDropsNothing() {
        let arranged = RoomBlend.arrange(
            [candidate("a", score: 0.9), candidate("b", score: 0.1)],
            room: [profile("actor", affinities: ["a": 0.1])], actor: profile("actor"), timeArtists: [])

        #expect(arranged.compactMap(\.track.artistId) == ["a", "b"])
    }

    @Test func anArtistAnotherRemoteDislikesIsDroppedFromTheRoom() {
        let actor = profile("actor", affinities: ["a": 0.8, "b": 0.8])
        let other = profile("other", negative: ["b": -0.8])
        let arranged = RoomBlend.arrange(
            [candidate("a", score: 0.5), candidate("b", score: 0.9)], room: [actor, other], actor: actor,
            timeArtists: [])

        #expect(arranged.compactMap(\.track.artistId) == ["a"])
    }

    @Test func sharedArtistsComeFirstInBlendedOrderAheadOfHigherRankedSoloArtists() {
        let actor = profile("actor", affinities: ["a": 0.8, "b": 0.6, "c": 0.9])
        let other = profile("other", affinities: ["a": 0.2, "b": 0.6])
        let arranged = RoomBlend.arrange(
            [candidate("c", score: 0.9), candidate("a", score: 0.1), candidate("b", score: 0.2)],
            room: [actor, other], actor: actor, timeArtists: [])

        #expect(arranged.compactMap(\.track.artistId) == ["b", "a", "c"])
    }

    @Test func theTimeOfDayTagAppearsOnlyForArtistsPlayedInThatBucket() {
        let actor = profile("actor", affinities: ["a": 0.1, "b": 0.1])
        let arranged = RoomBlend.arrange(
            [candidate("a", score: 0.5), candidate("b", score: 0.4)], room: [actor], actor: actor,
            timeArtists: ["a"])

        #expect(arranged.first { $0.track.artistId == "a" }?.evidence == ["matches_time_of_day"])
        #expect(arranged.first { $0.track.artistId == "b" }?.evidence == [])
    }

    @Test func aNegativeTasteScoreIsANegativePreferenceAndAPositiveOneAnAffinity() {
        let applied = profile("actor").applyingTaste(["liked": 0.5, "skipped": -0.6])

        #expect(applied.affinities == ["liked": 0.5])
        #expect(applied.negativePreferences == ["skipped": -0.6])
    }
}
