package app.cadenza.remote.model

import app.cadenza.remote.data.Song
import app.cadenza.remote.data.SongStatistic
import org.json.JSONArray
import org.json.JSONObject

/** The stored preference that lets this Remote send its taste digest at hello. It stays off until the user turns it on. */
internal const val TASTE_DIGEST_OPT_IN = "taste_digest_opt_in"

private const val MAXIMUM_ARTISTS = 20
private const val MAXIMUM_FAVORITES = 200
private const val MAXIMUM_TEXT = 200

/**
 * The taste summary a Remote sends at hello after the user opts in. It names artists and favorite songs only, so the Host
 * can personalize a new pairing before its own history builds up. This Remote keeps no genre data, so genres stay empty.
 */
internal fun tasteDigest(
    statistics: List<SongStatistic>,
    favorites: List<Song>,
): JSONObject =
    JSONObject()
        .put("top_artists", JSONArray(topArtists(statistics)))
        .put("top_genres", JSONArray())
        .put("favorited_track_ids", JSONArray(favorites.map { it.id }.distinct().take(MAXIMUM_FAVORITES)))

private fun topArtists(statistics: List<SongStatistic>): List<String> =
    statistics
        .filter { it.artist.isNotBlank() }
        .groupBy { it.artist }
        .entries
        .sortedByDescending { entry -> entry.value.sumOf { it.plays } }
        .take(MAXIMUM_ARTISTS)
        .map { it.key.take(MAXIMUM_TEXT) }
