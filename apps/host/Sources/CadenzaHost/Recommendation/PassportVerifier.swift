import CryptoKit
import Foundation

enum RecommendationPassportError: Error, LocalizedError {
    case malformed(String)
    case stale
    case replay
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .malformed(let message): message
        case .stale: "The recommendation passport has expired."
        case .replay: "The recommendation passport sequence is out of order."
        case .unauthorized: "The recommendation passport is not authorized for this Remote."
        }
    }
}

struct RecommendationPassportVerifier {
    private let decoder: JSONDecoder

    init() {
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func verify(
        _ signed: SignedRecommendationPassport,
        remoteId: String,
        previousSequence: Int64,
        nowMs: Int64 = wallMs()
    ) throws -> RecommendationPassport {
        guard signed.payloadBase64.count <= CREEConstants.maximumPayloadBytes * 2 else {
            throw RecommendationPassportError.malformed("The recommendation passport is too large.")
        }
        guard let payload = Data(base64Encoded: signed.payloadBase64), payload.count <= CREEConstants.maximumPayloadBytes,
            let keyData = Data(base64Encoded: signed.publicKeyBase64),
            let signature = Data(base64Encoded: signed.signatureBase64)
        else { throw RecommendationPassportError.malformed("The recommendation passport encoding is invalid.") }
        let key: P256.Signing.PublicKey
        do { key = try P256.Signing.PublicKey(rawRepresentation: keyData) }
        catch { throw RecommendationPassportError.malformed("The recommendation passport key is invalid.") }
        guard let ecdsaSignature = try? P256.Signing.ECDSASignature(derRepresentation: signature),
            key.isValidSignature(ecdsaSignature, for: payload) else {
            throw RecommendationPassportError.unauthorized
        }
        let passport: RecommendationPassport
        do { passport = try decoder.decode(RecommendationPassport.self, from: payload) }
        catch { throw RecommendationPassportError.malformed("The recommendation passport payload is invalid.") }
        try validate(passport, remoteId: remoteId, previousSequence: previousSequence, nowMs: nowMs)
        return passport
    }

    func materialize(_ passport: RecommendationPassport, remoteId: String) throws -> RecommendationProfile {
        try validate(passport, remoteId: remoteId, previousSequence: passport.sequence - 1, nowMs: passport.issuedAtMs)
        return RecommendationProfile(
            remoteId: remoteId, passportSequence: passport.sequence, expiresAtMs: passport.expiresAtMs,
            affinities: passport.affinities, transitions: passport.transitions,
            negativePreferences: passport.negativePreferences, recent: passport.recent,
            noveltyBudget: passport.noveltyBudget, sessionIntent: passport.sessionIntent,
            provenance: passport.provenance)
    }

    private func validate(
        _ passport: RecommendationPassport, remoteId: String, previousSequence: Int64, nowMs: Int64
    ) throws {
        guard passport.schemaVersion == CREEConstants.schemaVersion,
            passport.modelVersion == CREEConstants.modelVersion,
            passport.sequence > previousSequence,
            passport.sequence > 0,
            passport.issuedAtMs <= nowMs + 60_000,
            passport.expiresAtMs > nowMs,
            passport.expiresAtMs - passport.issuedAtMs <= 7 * 24 * 60 * 60 * 1000,
            ["minimal", "balanced", "full_local_network"].contains(passport.disclosure),
            ["paused", "balanced", "full"].contains(passport.consent),
            passport.affinities.count <= CREEConstants.maximumAffinities,
            passport.transitions.count <= CREEConstants.maximumTransitions,
            passport.recent.count <= 100,
            passport.noveltyBudget.isFinite, (0...1).contains(passport.noveltyBudget),
            passport.privacyBudget.isFinite, (0...1).contains(passport.privacyBudget)
        else {
            if passport.sequence <= previousSequence { throw RecommendationPassportError.replay }
            if passport.expiresAtMs <= nowMs { throw RecommendationPassportError.stale }
            throw RecommendationPassportError.malformed("The recommendation passport violates its bounds.")
        }
        for value in Array(passport.affinities.values) + Array(passport.negativePreferences.values) {
            guard value.isFinite, (-1...1).contains(value) else {
                throw RecommendationPassportError.malformed("The recommendation passport contains an invalid score.")
            }
        }
        for transition in passport.transitions {
            guard transition.weight.isFinite, transition.weight >= 0, transition.weight <= 1,
                transition.confidence.isFinite, (0...1).contains(transition.confidence),
                ["remote", "host", "music", "derived"].contains(transition.source)
            else { throw RecommendationPassportError.malformed("The recommendation passport contains an invalid transition.") }
        }
        _ = remoteId
    }
}
