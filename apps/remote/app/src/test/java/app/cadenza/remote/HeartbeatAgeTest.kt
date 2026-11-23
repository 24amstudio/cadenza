package app.cadenza.remote

import app.cadenza.remote.model.heartbeatAgeLabel
import org.junit.Assert.assertEquals
import org.junit.Test

class HeartbeatAgeTest {
    @Test
    fun aRemoteThatNeverHeardTheHostReportsNoAgeInsteadOfTimeSinceBoot() {
        assertEquals("none", heartbeatAgeLabel(lastSeenAt = 0L, now = 39_045_360L))
    }

    @Test
    fun aSeenFrameReportsItsAgeAndNeverANegativeOne() {
        assertEquals("1500", heartbeatAgeLabel(lastSeenAt = 10_000L, now = 11_500L))
        assertEquals("0", heartbeatAgeLabel(lastSeenAt = 12_000L, now = 11_500L))
    }
}
