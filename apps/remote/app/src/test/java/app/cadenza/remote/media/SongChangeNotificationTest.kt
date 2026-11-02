package app.cadenza.remote.media

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SongChangeNotificationTest {
    @Test
    fun newOccurrenceWhileConnectedIsASongChange() {
        assertTrue(isSongChange(connected = true, previous = "first", current = "second"))
    }

    @Test
    fun firstOccurrenceAfterConnectingIsNotAChange() {
        assertFalse(isSongChange(connected = true, previous = null, current = "second"))
    }

    @Test
    fun repeatedStateForTheSameOccurrenceIsNotAChange() {
        assertFalse(isSongChange(connected = true, previous = "same", current = "same"))
    }

    @Test
    fun changesWhileDisconnectedAreNotNotified() {
        assertFalse(isSongChange(connected = false, previous = "first", current = "second"))
    }
}
