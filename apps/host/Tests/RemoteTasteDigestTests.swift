import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct RemoteTasteDigestTests {
    private func digest(artists: [String] = []) -> RemoteTasteDigest {
        RemoteTasteDigest(topArtists: artists, topGenres: [], favoritedTrackIds: [])
    }

    private func profile(affinities: [String: Double] = [:], negative: [String: Double] = [:]) -> RecommendationProfile
    {
        RecommendationProfile(
            remoteId: "remote-a", passportSequence: 1, expiresAtMs: 0, affinities: affinities, transitions: [],
            negativePreferences: negative, recent: [], noveltyBudget: 0, sessionIntent: nil, provenance: [:])
    }

    @Test func aDigestOverTheProtocolLimitsIsRejectedAndOneAtTheLimitIsKept() throws {
        let atLimit = digest(artists: Array(repeating: "artist", count: 20))
        #expect(try atLimit.validated() == atLimit)
        #expect(throws: CadenzaError.self) {
            try digest(artists: Array(repeating: "artist", count: 21)).validated()
        }
        #expect(throws: CadenzaError.self) {
            try digest(artists: [""]).validated()
        }
    }

    @Test func seedingFillsOnlyArtistsTheProfileHasNoOpinionAbout() {
        let seeded = digest(artists: ["known", "disliked", "new"]).seeding(
            profile(affinities: ["known": 0.9], negative: ["disliked": -0.8]))

        #expect(seeded.affinities == ["known": 0.9, "new": RemoteTasteDigest.priorAffinity])
        #expect(seeded.negativePreferences == ["disliked": -0.8])
    }

    @Test func theLatestDigestReplacesTheStoredOneAndRemovalClearsIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadenza-digest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try Database(url: directory.appendingPathComponent("test.sqlite"))
        _ = try database.run(
            "INSERT INTO paired_remotes(remote_id,display_name,credential_reference,paired_at_ms) VALUES(?,?,?,?)",
            [.text("remote-a"), .text("Remote a"), .text("host.remote-a"), .integer(0)])
        let digests = TasteDigestStore(database: database)

        try digests.save(digest(artists: ["first"]), remoteId: "remote-a", at: Date())
        try digests.save(digest(artists: ["second"]), remoteId: "remote-a", at: Date())
        let replaced = try digests.load(remoteId: "remote-a")
        #expect(replaced?.topArtists == ["second"])

        try digests.remove(remoteId: "remote-a")
        let removed = try digests.load(remoteId: "remote-a")
        #expect(removed == nil)
    }
}
