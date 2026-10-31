package app.cadenza.remote.search

import app.cadenza.remote.data.Song
import app.cadenza.remote.data.SongStatistic
import java.text.Normalizer
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.min

// A score at this level means a result contains what was typed; below it, a result is only loosely related.
internal const val TEXT_MATCH_THRESHOLD = 55

private val combiningMarks = Regex("\\p{Mn}+")
private val separators = Regex("[^\\p{L}\\p{N}]+")

// Accents, case, and punctuation do not change what someone means, so they are ignored when comparing.
internal fun normalizeSearchText(value: String): String =
    Normalizer
        .normalize(value, Normalizer.Form.NFD)
        .replace(combiningMarks, "")
        .lowercase()
        .split(separators)
        .filter { it.isNotEmpty() }
        .joinToString(" ")

// Edit distance with an early exit, so a long word is abandoned as soon as it cannot match.
internal fun withinEditDistance(
    a: String,
    b: String,
    limit: Int,
): Boolean {
    if (abs(a.length - b.length) > limit) return false
    var previous = IntArray(b.length + 1) { it }
    for (i in 1..a.length) {
        val current = IntArray(b.length + 1)
        current[0] = i
        var rowMinimum = current[0]
        for (j in 1..b.length) {
            val cost = if (a[i - 1] == b[j - 1]) 0 else 1
            current[j] = minOf(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            rowMinimum = minOf(rowMinimum, current[j])
        }
        if (rowMinimum > limit) return false
        previous = current
    }
    return previous[b.length] <= limit
}

// Short words must match exactly. Longer words tolerate typos, so "pelukn" still finds "pelukan".
internal fun typoAllowance(word: String): Int =
    when {
        word.length >= 7 -> 2
        word.length >= 4 -> 1
        else -> 0
    }

// How well one normalized field matches a normalized query, from exact (100) down to a substring (40).
internal fun fieldMatch(
    field: String,
    query: String,
): Int {
    if (field.isEmpty() || query.isEmpty()) return 0
    val words = field.split(' ')
    val tokens = query.split(' ')
    return when {
        field == query -> 100
        field.startsWith(query) -> 90
        tokens.all { token -> words.any { it.startsWith(token) } } -> 75
        tokens.all { token ->
            val allowance = typoAllowance(token)
            words.any { word ->
                withinEditDistance(word.take(token.length), token, allowance) || withinEditDistance(word, token, allowance)
            }
        } -> 55
        field.contains(query) -> 40
        else -> 0
    }
}

// The best match across title, artist, and album. A title match counts most; an artist or album match counts less.
internal fun textScore(
    song: Song,
    normalizedQuery: String,
): Int {
    if (normalizedQuery.isEmpty()) return 0
    val title = normalizeSearchText(song.title)
    val artist = normalizeSearchText(song.artist)
    val album = normalizeSearchText(song.album)
    return maxOf(
        fieldMatch(title, normalizedQuery),
        (fieldMatch(artist, normalizedQuery) * 0.85).toInt(),
        (fieldMatch("$title $artist", normalizedQuery) * 0.9).toInt(),
        (fieldMatch(album, normalizedQuery) * 0.5).toInt(),
    )
}

// What this Remote's user has done with a song. Favorites and plays break ties between equally good matches.
internal data class SongSignals(
    val favorite: Boolean,
    val plays: Long,
) {
    // A favorite adds 30, and plays add up to 40 on a logarithmic scale, so heavy listening cannot bury a better match.
    val boost: Int get() = (if (favorite) 30 else 0) + min(40.0, ln(1.0 + plays) * 12.0).toInt()
}

internal class SearchSignals(
    favorites: List<Song>,
    statistics: List<SongStatistic>,
) {
    private val favoriteKeys = favorites.mapTo(HashSet()) { key(it.source, it.id) }
    private val plays = statistics.associate { key(it.source, it.songId) to it.plays }

    fun of(song: Song): SongSignals {
        val identity = key(song.source, song.id)
        return SongSignals(favorite = identity in favoriteKeys, plays = plays[identity] ?: 0L)
    }

    private fun key(
        source: String,
        id: String,
    ) = "$source:$id"
}

internal data class RankedSong(
    val song: Song,
    val score: Int,
    val signals: SongSignals,
)

// Ranks the Host's results by how well they match the query, then by what the user favorited or played.
// Sorting is stable, so equal scores keep the order the Host returned.
internal fun rankSongs(
    query: String,
    songs: List<Song>,
    signals: SearchSignals,
): List<RankedSong> {
    val normalized = normalizeSearchText(query)
    return songs
        .map { song ->
            val personal = signals.of(song)
            RankedSong(song, textScore(song, normalized) + personal.boost, personal)
        }.sortedByDescending { it.score }
}

// Ranks the typed query's results beside the corrected title's results. A song found by both keeps its best score.
internal fun rankSearch(
    query: String,
    results: List<Song>,
    correction: String?,
    correctedResults: List<Song>,
    signals: SearchSignals,
): List<RankedSong> =
    (rankSongs(query, results, signals) + rankSongs(correction.orEmpty(), correctedResults, signals))
        .groupBy { it.song.source + ":" + it.song.id }
        .values
        .map { duplicates -> duplicates.maxBy { it.score } }
        .sortedByDescending { it.score }
