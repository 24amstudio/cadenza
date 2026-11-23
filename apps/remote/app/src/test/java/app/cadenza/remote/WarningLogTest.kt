package app.cadenza.remote

import app.cadenza.remote.model.WARNING_LOG_INTERVAL_MS
import app.cadenza.remote.model.shouldLogWarning
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WarningLogTest {
    @Test
    fun aRepeatedNoticeIsLoggedOncePerInterval() {
        val first = "This song is not in your Host library."
        val logged = first to 1_000L

        assertFalse(shouldLogWarning(logged, first, now = 1_000L + WARNING_LOG_INTERVAL_MS - 1))
        assertTrue(shouldLogWarning(logged, first, now = 1_000L + WARNING_LOG_INTERVAL_MS))
    }

    @Test
    fun aDifferentNoticeIsAlwaysLogged() {
        assertTrue(shouldLogWarning("Old notice" to 1_000L, "New notice", now = 1_001L))
        assertTrue(shouldLogWarning(null, "First notice", now = 0L))
    }
}
