package app.cadenza.remote

import app.cadenza.remote.data.AutoPlayItem
import app.cadenza.remote.data.CurrentPlayback
import app.cadenza.remote.data.Song
import app.cadenza.remote.model.AutoPlayRequest
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.model.canRequestAutoPlay
import app.cadenza.remote.model.matches
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutoPlayRequestTest {
    private val item = AutoPlayItem("Tiny Dancer", "Elton John")

    private fun catalogSong(
        title: String,
        artist: String,
    ) = Song(source = "catalog", id = "1", title = title, artist = artist)

    private fun readyState(
        capabilities: Set<String> = setOf("queue.play-next"),
        current: CurrentPlayback? = null,
        crossEdits: Boolean = true,
    ) = RemoteState(
        connected = true,
        capabilities = capabilities,
        snapshot = testSnapshot(current = current).copy(allowCrossRemoteEdits = crossEdits),
    )

    @Test
    fun aVersionSuffixDoesNotChangeTheRecording() {
        val remastered = AutoPlayItem("Goodbye Yellow Brick Road (Remastered 2014)", "Elton John")

        assertTrue(remastered.matches(catalogSong("Goodbye Yellow Brick Road", "Elton John")))
    }

    @Test
    fun aSongWithTheSameTitleByAnotherArtistIsNotTheAutoPlayRow() {
        assertFalse(item.matches(catalogSong("Tiny Dancer", "Someone Else")))
    }

    @Test
    fun aDifferentTitleByTheSameArtistIsNotTheAutoPlayRow() {
        assertFalse(item.matches(catalogSong("Rocket Man", "Elton John")))
    }

    @Test
    fun aRequestWaitsUntilTheHostReportsTheQueueSynchronized() {
        assertFalse(RemoteState(connected = true).canRequestAutoPlay(next = false))
        assertFalse(RemoteState(connected = true).canRequestAutoPlay(next = true))
    }

    @Test
    fun playNextNeedsTheHostCapability() {
        assertFalse(readyState(capabilities = emptySet()).canRequestAutoPlay(next = true))
        assertTrue(readyState().canRequestAutoPlay(next = true))
    }

    @Test
    fun playNowIsRefusedWhileAnotherPersonsRequestPlaysAndCrossEditsAreOff() {
        val othersRequest =
            CurrentPlayback(
                occurrenceId = "00000000-0000-4000-8000-000000000010",
                entryId = "entry",
                requestedBy = "other-remote",
                requesterName = "Kitchen",
                song = testSong("9"),
                positionMs = 0,
                sampledAtHostMs = 0,
            )

        assertFalse(readyState(current = othersRequest, crossEdits = false).canRequestAutoPlay(next = false))
        assertTrue(readyState(current = othersRequest, crossEdits = false).canRequestAutoPlay(next = true))
        assertTrue(readyState(current = othersRequest, crossEdits = true).canRequestAutoPlay(next = false))
    }

    @Test
    fun aRequestInFlightBlocksAnotherUntilItFinishes() {
        val pending = readyState().copy(autoPlayRequest = AutoPlayRequest(item, next = false))

        assertFalse(pending.canRequestAutoPlay(next = false))
        assertFalse(pending.canRequestAutoPlay(next = true))
    }
}
