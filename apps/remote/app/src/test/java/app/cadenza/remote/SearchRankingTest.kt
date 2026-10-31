package app.cadenza.remote

import app.cadenza.remote.data.Song
import app.cadenza.remote.data.SongStatistic
import app.cadenza.remote.search.SearchHistory
import app.cadenza.remote.search.SearchSignals
import app.cadenza.remote.search.SuggestionKind
import app.cadenza.remote.search.composeSuggestions
import app.cadenza.remote.search.correctionFor
import app.cadenza.remote.search.didYouMean
import app.cadenza.remote.search.fieldMatch
import app.cadenza.remote.search.normalizeSearchText
import app.cadenza.remote.search.rankSearch
import app.cadenza.remote.search.rankSongs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SearchRankingTest {
    private val pelukan = song("pelukan", "Untuk Perempuan Yang Sedang Di Pelukan", "Payung Teduh")
    private val akad = song("akad", "Akad", "Payung Teduh")
    private val akadCover = song("cover", "Akad", "Another Artist")

    @Test
    fun accentsCaseAndTyposStillFindTheSong() {
        assertEquals(normalizeSearchText("Pelukán"), normalizeSearchText("pelukan"))
        assertTrue(fieldMatch(normalizeSearchText(pelukan.title), normalizeSearchText("pelukn")) > 0)
        assertEquals(0, fieldMatch(normalizeSearchText(akad.title), normalizeSearchText("zzz")))
    }

    @Test
    fun aFavoriteWinsOverAnEquallyGoodMatch() {
        val signals = SearchSignals(favorites = listOf(akadCover), statistics = emptyList())

        assertEquals(listOf("cover", "akad"), rankSongs("akad", listOf(akad, akadCover), signals).map { it.song.id })
    }

    @Test
    fun aPlayedSongWinsOverAnUnplayedOneWithTheSameText() {
        val signals =
            SearchSignals(
                favorites = emptyList(),
                statistics = listOf(SongStatistic("catalog", "akad", "Akad", "Payung Teduh", plays = 12, playedMs = 0)),
            )

        assertEquals(listOf("akad", "cover"), rankSongs("akad", listOf(akadCover, akad), signals).map { it.song.id })
    }

    @Test
    fun aBetterTextMatchOutranksPersonalHabitsOnAWeakMatch() {
        val signals = SearchSignals(favorites = listOf(pelukan), statistics = emptyList())
        val ranked = rankSongs("akad", listOf(pelukan, akad), signals).map { it.song.id }

        assertEquals("akad", ranked.first())
    }

    @Test
    fun suggestionsListWhatTheUserAlreadyKnowsBeforeAppleCompletions() {
        val suggestions =
            composeSuggestions(
                query = "akad",
                recent = listOf("akad payung"),
                terms = listOf("akad payung teduh", "akademie"),
                favorites = listOf(akad),
                statistics = listOf(SongStatistic("catalog", "akad", "Akad", "Payung Teduh", plays = 3, playedMs = 0)),
                appleSongs = listOf(akad, akadCover),
            )

        assertEquals(SuggestionKind.Recent, suggestions.first().kind)
        assertEquals(1, suggestions.count { it.song?.id == "akad" })
        assertTrue(suggestions.any { it.kind == SuggestionKind.Term && it.text == "akad payung teduh" })
    }

    @Test
    fun anEmptyQueryShowsOnlyRecentSearches() {
        val suggestions = composeSuggestions("  ", listOf("one", "two"), emptyList(), listOf(akad), emptyList(), emptyList())

        assertEquals(listOf("one", "two"), suggestions.map { it.text })
    }

    @Test
    fun aNearMissIsOfferedFromWhatTheUserKnows() {
        assertEquals("Untuk Perempuan Yang Sedang Di Pelukan", didYouMean("pelukn", listOf("Untuk Perempuan Yang Sedang Di Pelukan")))
        assertNull(didYouMean("ak", listOf("akad")))
    }

    @Test
    fun recentSearchesStayUniqueNewestFirstAndCapped() {
        var recent = emptyList<String>()
        repeat(14) { recent = SearchHistory.add(recent, "query $it") }
        recent = SearchHistory.add(recent, "QUERY 3")

        assertEquals(12, recent.size)
        assertEquals("QUERY 3", recent.first())
        assertEquals(1, recent.count { normalizeSearchText(it) == "query 3" })
        assertEquals(recent, SearchHistory.decode(SearchHistory.encode(recent)))
    }

    @Test
    fun aCorrectionIsSearchedOnlyWhenNoResultMatchesWhatWasTyped() {
        assertEquals(pelukan.title, correctionFor("pelukn", listOf(akad), listOf(pelukan.title)))
        assertNull(correctionFor("akad", listOf(akad), listOf(pelukan.title)))
    }

    @Test
    fun correctedResultsRankBesideTheTypedMatchesWithoutDuplicates() {
        val signals = SearchSignals(favorites = emptyList(), statistics = emptyList())
        val ranked = rankSearch("pelukn", listOf(akad, pelukan), pelukan.title, listOf(pelukan), signals)

        assertEquals(listOf("pelukan", "akad"), ranked.map { it.song.id })
    }

    private fun song(
        id: String,
        title: String,
        artist: String,
    ) = Song(source = "catalog", id = id, title = title, artist = artist)
}
