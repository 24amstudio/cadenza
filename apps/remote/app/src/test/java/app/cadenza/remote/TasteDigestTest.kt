package app.cadenza.remote

import app.cadenza.remote.data.Song
import app.cadenza.remote.data.SongStatistic
import app.cadenza.remote.model.tasteDigest
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Test

class TasteDigestTest {
    private fun play(
        artist: String,
        plays: Long,
    ) = SongStatistic(
        source = "catalog",
        songId = "$artist-$plays",
        title = "Track",
        artist = artist,
        plays = plays,
        playedMs = 0,
    )

    private fun favorite(id: String) = Song(source = "library", id = id, title = "Track", artist = "Artist")

    private fun strings(array: JSONArray): List<String> = (0 until array.length()).map { array.getString(it) }

    @Test
    fun artistsRankByTotalPlaysAndBlankArtistsAreLeftOut() {
        val digest =
            tasteDigest(
                listOf(play("A", 5), play("B", 2), play("A", 3), play("", 100)),
                emptyList(),
            )

        assertEquals(listOf("A", "B"), strings(digest.getJSONArray("top_artists")))
    }

    @Test
    fun theDigestKeepsAtMostTwentyArtistsAndDistinctFavorites() {
        val digest =
            tasteDigest(
                (1..25).map { play("artist $it", 1) },
                listOf(favorite("1"), favorite("1"), favorite("2")),
            )

        assertEquals(20, digest.getJSONArray("top_artists").length())
        assertEquals(listOf("1", "2"), strings(digest.getJSONArray("favorited_track_ids")))
    }

    @Test
    fun withNoHistoryEveryListIsEmpty() {
        val digest = tasteDigest(emptyList(), emptyList())

        assertEquals(0, digest.getJSONArray("top_artists").length())
        assertEquals(0, digest.getJSONArray("top_genres").length())
        assertEquals(0, digest.getJSONArray("favorited_track_ids").length())
    }
}
