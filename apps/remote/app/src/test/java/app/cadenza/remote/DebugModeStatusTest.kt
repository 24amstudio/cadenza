package app.cadenza.remote

import app.cadenza.remote.debugmode.debugStatusLine
import org.junit.Assert.assertEquals
import org.junit.Test

class DebugModeStatusTest {
    @Test
    fun theStatusLineNamesEachFieldAHostTestReads() {
        val line =
            debugStatusLine(
                connected = true,
                connecting = false,
                transportMode = "hybrid",
                profileName = "Mac",
                issue = null,
                playing = true,
                title = "Song",
                clockUncertaintyMs = null,
            )

        assertEquals(
            "connected=true connecting=false transport=hybrid host=Mac playing=true title=Song issue= clock_uncertainty_ms=none",
            line,
        )
    }
}
