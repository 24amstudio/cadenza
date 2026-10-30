import Foundation

struct RecommendationRanker: Sendable {
    func rank(
        candidates: [RecommendationCandidate], profile: RecommendationProfile, context: RecommendationContext
    ) -> [RecommendationCandidate] {
        var unique: [String: RecommendationCandidate] = [:]
        for var candidate in candidates.prefix(CREEConstants.maximumCandidates) {
            guard candidate.availability else { continue }
            if let existing = unique[candidate.id] {
                candidate.evidence = Array(Set(existing.evidence + candidate.evidence)).sorted().prefix(8).map { $0 }
                candidate.confidence = max(candidate.confidence, existing.confidence)
                candidate.source = existing.source == "cadenza" ? existing.source : candidate.source
            }
            candidate.score = score(candidate, profile: profile, context: context)
            unique[candidate.id] = candidate
        }
        return unique.values.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.id < rhs.id : lhs.score > rhs.score
        }
    }

    private func score(
        _ candidate: RecommendationCandidate, profile: RecommendationProfile, context: RecommendationContext
    ) -> Double {
        let identity = candidate.id
        let artist = candidate.track.artistId ?? candidate.song.artist
        let personal = profile.affinities[identity] ?? profile.affinities[artist] ?? 0
        let negative = profile.negativePreferences[identity] ?? profile.negativePreferences[artist] ?? 0
        let transition = profile.transitions.filter {
            $0.to.source == candidate.track.source && $0.to.id == candidate.track.id
                && $0.from == (context.current ?? profile.recent.first)
        }.map { $0.weight * $0.confidence }.max() ?? 0
        let familiar = profile.recent.contains(candidate.track) ? 0.14 : 0
        let novelty = profile.noveltyBudget * (profile.recent.contains(candidate.track) ? 0 : 0.12)
        let contextFit = context.intent == profile.sessionIntent && context.intent != nil ? 0.1 : 0
        let apple = (candidate.applePrior ?? 0) * 0.06
        let fatigue = context.recent.filter { $0.artistId == candidate.track.artistId && candidate.track.artistId != nil }.count > 0 ? -0.16 : 0
        let completeness = candidate.metadataCompleteness * 0.06
        return personal * 0.42 + transition * 0.28 + familiar + novelty + contextFit + apple + completeness
            + candidate.confidence * 0.1 + negative * -0.34 + fatigue
    }
}

struct RecommendationFeedbackModel: Sendable {
    static let weights: [RecommendationOutcome: Double] = [
        .qualifiedPlay: 0.25, .earlySkip: -0.7, .lateSkip: -0.2, .replay: 0.8,
        .favorite: 0.9, .manualReplacement: -0.45, .queueRemoval: -0.08, .interruption: 0,
    ]

    func update(
        profile: RecommendationProfile, feedback: RecommendationFeedback, track: RecommendationTrack
    ) -> RecommendationProfile {
        var result = profile
        let delta = Self.weights[feedback.outcome] ?? 0
        guard delta != 0 else { return result }
        let key = track.source + ":" + track.id
        result.affinities[key, default: 0] = (result.affinities[key, default: 0] + delta).clamped(to: -1...1)
        if delta < 0 {
            result.negativePreferences[key, default: 0] =
                (result.negativePreferences[key, default: 0] + abs(delta) * 0.5).clamped(to: 0...1)
        }
        if feedback.outcome == .manualReplacement, let replacement = feedback.replacement {
            let replacementKey = replacement.source + ":" + replacement.id
            result.affinities[replacementKey, default: 0] =
                (result.affinities[replacementKey, default: 0] + 0.45).clamped(to: -1...1)
        }
        return result
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) }
}
