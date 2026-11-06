import Testing

@testable import CadenzaHost

struct StateCoverTests {
    @Test func aStateWithoutACoverOrWithACachedOneGoesOutAtOnce() {
        #expect(StateCover.coverToAwait(artworkUrl: nil, isCached: { _ in false }, alreadyWaited: nil) == nil)
        #expect(
            StateCover.coverToAwait(
                artworkUrl: "https://example.com/a.jpg", isCached: { _ in true }, alreadyWaited: nil) == nil)
    }

    @Test func aStateWaitsForAnUncachedCoverOnlyOnce() {
        let url = "https://example.com/a.jpg"

        #expect(StateCover.coverToAwait(artworkUrl: url, isCached: { _ in false }, alreadyWaited: nil) == url)
        // A cover that already timed out is not held again, so the next state does not wait on it.
        #expect(StateCover.coverToAwait(artworkUrl: url, isCached: { _ in false }, alreadyWaited: url) == nil)
        // A different cover is waited for.
        #expect(
            StateCover.coverToAwait(
                artworkUrl: "https://example.com/b.jpg", isCached: { _ in false }, alreadyWaited: url)
                == "https://example.com/b.jpg")
    }
}
