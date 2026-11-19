import Testing

@testable import CadenzaHost

struct SongRowMatcherTests {
    private let library = Song(
        source: "library", id: "ABCDEF0123456789", title: "Intro", artist: "Real Artist", album: "Debut",
        durationMs: 125_000)
    private let catalog = Song(source: "catalog", id: "1700000001", title: "Blinding Lights", artist: "The Weeknd")

    private func score(_ song: Song, _ texts: [String], linked: Bool = false, selected: Bool = false) -> Int {
        SongRowMatcher.score(song, texts: texts, linked: linked, selected: selected)
    }

    @Test func prefersTheRowWithTheMatchingArtistWhenTitlesRepeat() {
        let other = score(library, ["Intro", "Other Artist"])
        let real = score(library, ["Intro", "Real Artist \u{2014} Debut", "2:05"])

        #expect(other < SongRowMatcher.acceptance)
        #expect(SongRowMatcher.best([(row: "other", score: other), (row: "real", score: real)]) == "real")
    }

    @Test func acceptsDecoratedTruncatedAndAccentedLabels() {
        #expect(score(catalog, ["Blinding Lights (Remastered 2019)", "The Weeknd"]) >= SongRowMatcher.acceptance)
        #expect(score(catalog, ["Blinding Lig\u{2026}", "The Weeknd"]) >= SongRowMatcher.acceptance)
        #expect(score(catalog, ["Blinding Lights, The Weeknd, After Hours"]) >= SongRowMatcher.acceptance)
        let accented = Song(source: "library", id: "1", title: "Halo", artist: "Beyonc\u{00E9}")
        #expect(score(accented, ["HALO", "Beyonce"]) >= SongRowMatcher.acceptance)
    }

    @Test func rejectsADifferentRecordingOfTheSameTitle() {
        #expect(score(catalog, ["Blinding Lights (Live)", "The Weeknd"]) < SongRowMatcher.acceptance)
        #expect(score(catalog, ["Blinding Lights Remix Pack", "Someone Else"]) < SongRowMatcher.acceptance)
    }

    @Test func aLibraryTitleAloneIsNotEnoughButACatalogLinkTitleIs() {
        #expect(score(library, ["Intro"]) < SongRowMatcher.acceptance)
        #expect(score(library, ["Intro"], selected: true) >= SongRowMatcher.acceptance)
        #expect(score(catalog, ["Blinding Lights"]) >= SongRowMatcher.acceptance)
    }

    @Test func anIdentifierLinkWinsOverAnyTitle() {
        #expect(score(catalog, ["Unrelated"], linked: true) > score(catalog, ["Blinding Lights", "The Weeknd"]))
    }
}
