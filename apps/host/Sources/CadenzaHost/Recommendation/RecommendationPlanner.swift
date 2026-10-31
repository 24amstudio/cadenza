import Foundation

enum RecommendationPolicyDecision: Sendable, Equatable {
    case allowed
    case noCandidate
    case locked
    case disconnected
    case staleRevision
    case unavailable
    case explicitBlocked
    case duplicate
}

struct RecommendationPlanner: Sendable {
    func choose(
        ranked: [RecommendationCandidate], context: RecommendationContext, profile: RecommendationProfile,
        nowMs: Int64 = wallMs()
    ) -> (RecommendationPolicyDecision, RecommendationResult?) {
        guard !context.locked else { return (.locked, nil) }
        guard let candidate = ranked.first else { return (.noCandidate, nil) }
        guard candidate.availability else { return (.unavailable, nil) }
        guard context.explicitAllowed || candidate.song.title.isEmpty == false else { return (.explicitBlocked, nil) }
        guard !context.queue.contains(where: { $0 == candidate.track }), context.current != candidate.track else {
            return (.duplicate, nil)
        }
        let confidence = max(0, min(1, candidate.score.sigmoid()))
        guard confidence >= 0.18 else { return (.noCandidate, nil) }
        let plan = identifier()
        return (
            .allowed,
            RecommendationResult(
                recommendationId: identifier(),
                planId: plan,
                passportSequence: profile.passportSequence,
                modelVersion: CREEConstants.modelVersion,
                candidate: candidate.track,
                confidence: confidence,
                evidence: candidate.evidence.prefix(8).map { $0 },
                expiresAtMs: nowMs + 60_000,
                provenance: candidate.source == "apple_autoplay" ? "apple_autoplay" : "cadenza"
            )
        )
    }
}

extension Double {
    func sigmoid() -> Double { 1 / (1 + exp(-self)) }
}
