import Foundation

struct RecommendationCandidateRetriever: Sendable {
    func retrieve(
        profile: RecommendationProfile, context: RecommendationContext, knownSongs: [SongIdentity: Song],
        appleCandidates: [RecommendationCandidate] = []
    ) -> [RecommendationCandidate] {
        var candidates: [RecommendationCandidate] = []
        for transition in profile.transitions where transition.from == context.current {
            if let song = knownSongs[transition.to.identity] {
                candidates.append(RecommendationCandidate(
                    track: transition.to, song: song, source: transition.source,
                    confidence: transition.confidence, evidence: ["kept after this song"], applePrior: nil,
                    metadataCompleteness: completeness(song), availability: true))
            }
        }
        for track in profile.recent {
            guard let song = knownSongs[track.identity] else { continue }
            candidates.append(RecommendationCandidate(
                track: track, song: song, source: "cadenza", confidence: 0.45,
                evidence: ["recent listening"], applePrior: nil, metadataCompleteness: completeness(song), availability: true))
        }
        candidates.append(contentsOf: appleCandidates.map { candidate in
            var copy = candidate
            copy.applePrior = copy.applePrior ?? 0.5
            copy.source = "apple_autoplay"
            copy.evidence = Array(Set(copy.evidence + ["Apple AutoPlay prior"]))
            return copy
        })
        return candidates
    }

    private func completeness(_ song: Song) -> Double {
        let fields = [song.title, song.artist, song.album].filter { !$0.isEmpty }.count
        return Double(fields) / 3
    }
}

extension RecommendationTrack {
    var identity: SongIdentity { SongIdentity(source: source, id: id) }
}
