import CryptoKit
import Foundation
import Testing
@testable import CadenzaHost

struct RecommendationTests {
    @Test func rankerPrefersPersonalFitAndRejectsDuplicates() {
        let track = RecommendationTrack(source: "catalog", id: "1", artistId: "artist", albumId: nil, versionId: nil)
        let profile = RecommendationProfile(
            remoteId: identifier(), passportSequence: 1, expiresAtMs: wallMs() + 10_000,
            affinities: ["catalog:1": 0.9], transitions: [], negativePreferences: [:], recent: [],
            noveltyBudget: 0.5, sessionIntent: nil, provenance: [:])
        let candidate = RecommendationCandidate(
            track: track, song: Song(source: "catalog", id: "1", title: "One", artist: "Artist"),
            source: "recent_history", confidence: 0.8, evidence: ["favorite"], applePrior: nil,
            metadataCompleteness: 1, availability: true)
        let context = RecommendationContext(
            current: nil, recent: [], queue: [], intent: nil, queuePhase: "empty", explicitAllowed: true,
            locked: false, queueRevision: 1, modelVersion: 1)
        let ranked = RecommendationRanker().rank(candidates: [candidate], profile: profile, context: context)
        #expect(ranked.first?.score ?? 0 > 0.3)
        #expect(RecommendationPlanner().choose(ranked: ranked, context: context, profile: profile).1 != nil)
    }

    @Test func signedPassportRejectsReplayAndAcceptsValidPayload() throws {
        let key = P256.Signing.PrivateKey()
        let passport = RecommendationPassport(
            sequence: 1, issuedAtMs: wallMs() - 100, expiresAtMs: wallMs() + 10_000,
            consent: "balanced", disclosure: "balanced", affinities: [:], transitions: [],
            negativePreferences: [:], recent: [], noveltyBudget: 0.5, sessionIntent: nil,
            privacyBudget: 1, provenance: [:])
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let payload = try encoder.encode(passport)
        let signed = SignedRecommendationPassport(
            payloadBase64: payload.base64EncodedString(), publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString(),
            signatureBase64: key.signature(for: payload).derRepresentation.base64EncodedString())
        let verifier = RecommendationPassportVerifier()
        #expect(try verifier.verify(signed, remoteId: identifier(), previousSequence: 0).sequence == 1)
        #expect(throws: RecommendationPassportError.self) {
            try verifier.verify(signed, remoteId: identifier(), previousSequence: 1)
        }
    }
}
