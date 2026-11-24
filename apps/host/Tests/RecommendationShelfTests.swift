import Testing

@testable import CadenzaHost

struct RecommendationShelfTests {
    private func candidate(_ index: Int, evidence: [String] = ["recent listening"]) -> RecommendationCandidate {
        RecommendationCandidate(
            track: RecommendationTrack(source: "catalog", id: "\(index)", artistId: "artist \(index)"),
            song: Song(source: "catalog", id: "\(index)", title: "Song \(index)", artist: "Artist \(index)"),
            source: "cadenza", confidence: 0.5, evidence: evidence, applePrior: nil, metadataCompleteness: 1,
            availability: true, score: 0.5)
    }

    @Test func aShelfKeepsTheRankingAndTheReasonTagsAndStopsAtItsLimit() {
        let ranked = (1...20).map { candidate($0, evidence: ["room_blend"]) }
        let shelf = RecommendationShelf.make(from: ranked)

        #expect(shelf.items.count == RecommendationShelf.itemLimit)
        #expect(shelf.items.first?.title == "Song 1")
        #expect(shelf.items.first?.evidence == ["room_blend"])
    }

    @Test func aShelfCapsEachItemsReasonsAtEight() {
        let reasons = (1...10).map { "reason \($0)" }
        let shelf = RecommendationShelf.make(from: [candidate(1, evidence: reasons)])

        #expect(shelf.items.first?.evidence.count == 8)
    }
}
