package app.cadenza.remote

import app.cadenza.remote.data.ArtworkDiskCache
import app.cadenza.remote.data.Song
import app.cadenza.remote.model.heldAlbumCover
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ArtworkCacheTest {
    @get:Rule
    val folder = TemporaryFolder()

    private fun song(
        id: String,
        album: String,
        url: String?,
    ) = Song(source = "library", id = id, title = id, artist = "Band", album = album, artworkUrl = url)

    @Test
    fun aHeldCoverOfTheSameAlbumStandsInForTheOtherTracks() {
        val queue = listOf(song("1", "Record", "a"), song("2", "Record", "b"), song("3", "Other", "c"))
        val held = setOf("a")

        assertEquals("a", heldAlbumCover("b", queue) { it in held })
        assertNull(heldAlbumCover("c", queue) { it in held })
    }

    @Test
    fun theDiskTierReturnsStoredBytesAndEvictsTheLeastRecentlyUsed() {
        var time = 0L
        val cache = ArtworkDiskCache(folder.newFolder("artwork"), maxBytes = 10) { ++time }

        cache.put("first", ByteArray(4) { 1 })
        cache.put("second", ByteArray(4) { 2 })
        assertArrayEquals(ByteArray(4) { 1 }, cache.get("first"))
        cache.put("third", ByteArray(4) { 3 })

        assertNull(cache.get("second"))
        assertArrayEquals(ByteArray(4) { 3 }, cache.get("third"))
    }
}
