import Foundation

enum CREEConstants {
    static let schemaVersion = 1
    static let modelVersion = 1
    static let maximumPayloadBytes = 64 * 1024
    static let maximumAffinities = 256
    static let maximumTransitions = 512
    static let maximumCandidates = 128
    static let maximumPlanHorizon = 4
}

struct RecommendationTrack: Codable, Hashable, Sendable {
    var source: String
    var id: String
    var artistId: String?
    var albumId: String?
    var versionId: String?
}

struct RecommendationFeature<Value: Codable & Sendable>: Codable, Sendable {
    var value: Value?
    var source: String
    var confidence: Double
    var freshnessMs: Int64
    var schemaVersion: Int
    var modelVersion: Int

    init(
        value: Value?, source: String, confidence: Double, freshnessMs: Int64,
        schemaVersion: Int = CREEConstants.schemaVersion, modelVersion: Int = CREEConstants.modelVersion
    ) {
        self.value = value
        self.source = source
        self.confidence = confidence
        self.freshnessMs = freshnessMs
        self.schemaVersion = schemaVersion
        self.modelVersion = modelVersion
    }
}

struct RecommendationTransition: Codable, Hashable, Sendable {
    var from: RecommendationTrack
    var to: RecommendationTrack
    var weight: Double
    var source: String
    var confidence: Double
    var freshnessMs: Int64
}

struct RecommendationPassport: Codable, Sendable {
    var schemaVersion: Int = CREEConstants.schemaVersion
    var modelVersion: Int = CREEConstants.modelVersion
    var sequence: Int64
    var issuedAtMs: Int64
    var expiresAtMs: Int64
    var consent: String
    var disclosure: String
    var affinities: [String: Double]
    var transitions: [RecommendationTransition]
    var negativePreferences: [String: Double]
    var recent: [RecommendationTrack]
    var noveltyBudget: Double
    var sessionIntent: String?
    var privacyBudget: Double
    var provenance: [String: RecommendationFeature<String>]
}

struct SignedRecommendationPassport: Codable, Sendable {
    var payloadBase64: String
    var publicKeyBase64: String
    var signatureBase64: String
}

struct RecommendationProfile: Codable, Sendable {
    var remoteId: String
    var passportSequence: Int64
    var expiresAtMs: Int64
    var affinities: [String: Double]
    var transitions: [RecommendationTransition]
    var negativePreferences: [String: Double]
    var recent: [RecommendationTrack]
    var noveltyBudget: Double
    var sessionIntent: String?
    var provenance: [String: RecommendationFeature<String>]
}

extension RecommendationProfile {
    /// A profile for a paired Remote that has not sent a passport yet.
    static func blank(remoteId: String) -> RecommendationProfile {
        RecommendationProfile(
            remoteId: remoteId, passportSequence: 0, expiresAtMs: 0, affinities: [:], transitions: [],
            negativePreferences: [:], recent: [], noveltyBudget: 0, sessionIntent: nil, provenance: [:])
    }

    /// Applies the Host's taste scores over the passport. Remote passports do not carry affinities yet, so the Host's
    /// ledger is the source. A negative score is a negative preference, so a skip counts only against the skipping Remote.
    func applyingTaste(_ scores: [String: Double]) -> RecommendationProfile {
        var applied = self
        for (artist, score) in scores {
            if score < 0 {
                applied.negativePreferences[artist] = score
            } else {
                applied.affinities[artist] = score
            }
        }
        return applied
    }
}

struct RecommendationCandidate: Sendable, Identifiable {
    var id: String { track.source + ":" + track.id }
    var track: RecommendationTrack
    var song: Song
    var source: String
    var confidence: Double
    var evidence: [String]
    var applePrior: Double?
    var metadataCompleteness: Double
    var availability: Bool
    var score: Double = 0
}

struct RecommendationContext: Sendable {
    var current: RecommendationTrack?
    var recent: [RecommendationTrack]
    var queue: [RecommendationTrack]
    var intent: String?
    var queuePhase: String
    var explicitAllowed: Bool
    var locked: Bool
    var queueRevision: Int64
    var modelVersion: Int
}

struct RecommendationResult: Codable, Sendable {
    var recommendationId: String
    var planId: String
    var passportSequence: Int64
    var modelVersion: Int
    var candidate: RecommendationTrack?
    var confidence: Double
    var evidence: [String]
    var expiresAtMs: Int64
    var provenance: String
    var mode: String = "planning"
}

/// A read-only list of ranked suggestions for a Remote's shelves. Nothing is queued or planned for these.
struct RecommendationShelf: Codable, Sendable, Equatable {
    static let itemLimit = 12

    struct Item: Codable, Sendable, Equatable {
        var track: RecommendationTrack
        var title: String
        var artist: String
        var evidence: [String]
    }

    var items: [Item]

    static func make(from ranked: [RecommendationCandidate]) -> RecommendationShelf {
        RecommendationShelf(
            items: ranked.prefix(itemLimit).map {
                Item(
                    track: $0.track, title: $0.song.title, artist: $0.song.artist,
                    evidence: Array($0.evidence.prefix(8)))
            })
    }
}

enum RecommendationOutcome: String, Codable, Sendable {
    case qualifiedPlay = "qualified_play"
    case earlySkip = "early_skip"
    case lateSkip = "late_skip"
    case replay
    case favorite
    case manualReplacement = "manual_replacement"
    case queueRemoval = "queue_removal"
    case interruption
}

struct RecommendationFeedback: Codable, Sendable {
    var recommendationId: String
    var outcome: RecommendationOutcome
    var track: RecommendationTrack? = nil
    var positionMs: Int64?
    var durationMs: Int64?
    var replacement: RecommendationTrack?
    var occurredAtMs: Int64
}

struct RecommendationShadowObservation: Codable, Sendable {
    var observationId: String
    var apple: RecommendationTrack?
    var cree: RecommendationTrack?
    var selected: RecommendationTrack?
    var provenanceConfidence: Double
    var outcome: String?
    var observedAtMs: Int64
}
