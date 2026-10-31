package app.cadenza.remote.search

import app.cadenza.remote.data.Song
import app.cadenza.remote.data.SongStatistic

internal enum class SuggestionKind {
    Recent,
    Term,
    Favorite,
    Played,
    Song,
}

internal data class SearchSuggestion(
    val kind: SuggestionKind,
    val text: String,
    val song: Song? = null,
)

// Autocomplete puts what the user already searched or played first, then Apple's completions, then the songs the
// user favorited or played that match, then Apple's top songs. Duplicates are dropped and the list stays short.
internal fun composeSuggestions(
    query: String,
    recent: List<String>,
    terms: List<String>,
    favorites: List<Song>,
    statistics: List<SongStatistic>,
    appleSongs: List<Song>,
    limit: Int = 8,
): List<SearchSuggestion> {
    val normalized = normalizeSearchText(query)
    if (normalized.isEmpty()) return recent.take(limit).map { SearchSuggestion(SuggestionKind.Recent, it) }
    val played =
        statistics
            .filter { it.plays > 0 }
            .map { Song(source = it.source, id = it.songId, title = it.title, artist = it.artist) }
    val suggestions =
        buildList {
            recent
                .filter { fieldMatch(normalizeSearchText(it), normalized) >= TEXT_MATCH_THRESHOLD }
                .take(3)
                .forEach { add(SearchSuggestion(SuggestionKind.Recent, it)) }
            terms
                .filter { fieldMatch(normalizeSearchText(it), normalized) >= TEXT_MATCH_THRESHOLD }
                .take(3)
                .forEach { add(SearchSuggestion(SuggestionKind.Term, it)) }
            favorites
                .filter { textScore(it, normalized) >= TEXT_MATCH_THRESHOLD }
                .take(3)
                .forEach { add(SearchSuggestion(SuggestionKind.Favorite, it.title, it)) }
            played
                .filter { textScore(it, normalized) >= TEXT_MATCH_THRESHOLD }
                .take(2)
                .forEach { add(SearchSuggestion(SuggestionKind.Played, it.title, it)) }
            appleSongs
                .take(3)
                .forEach { add(SearchSuggestion(SuggestionKind.Song, it.title, it)) }
        }
    return suggestions
        .distinctBy { it.song?.let { song -> song.source + ":" + song.id } ?: normalizeSearchText(it.text) }
        .take(limit)
}

// The closest thing the user has typed or favorited to a query, or null when nothing is close enough to be a typo.
internal fun didYouMean(
    query: String,
    candidates: List<String>,
): String? {
    val normalized = normalizeSearchText(query)
    val allowance = typoAllowance(normalized)
    if (allowance == 0) return null
    return candidates.firstOrNull { candidate ->
        val text = normalizeSearchText(candidate)
        // A typo usually targets one word of a longer title, so "pelukn" must reach "... Pelukan" word by word.
        text.isNotEmpty() &&
            text != normalized &&
            (withinEditDistance(text, normalized, allowance) || text.split(' ').any { withinEditDistance(it, normalized, allowance) })
    }
}

// A search that finds no real match is worth one more search for the title the user most likely meant.
internal fun correctionFor(
    query: String,
    results: List<Song>,
    candidates: List<String>,
): String? {
    val normalized = normalizeSearchText(query)
    if (results.any { textScore(it, normalized) >= TEXT_MATCH_THRESHOLD }) return null
    return didYouMean(query, candidates)
}
