package app.cadenza.remote

import app.cadenza.remote.model.FailureSeverity
import app.cadenza.remote.model.failureSeverity
import org.junit.Assert.assertEquals
import org.junit.Test

class FailureSeverityTest {
    @Test
    fun fatalHostProblemsNeedTheUserToActOutsideTheControl() {
        listOf("music_permission", "authentication", "revoked", "database_corrupt").forEach {
            assertEquals(it, FailureSeverity.Fatal, failureSeverity(it))
        }
    }

    @Test
    fun requestProblemsStayAsWarningsThatDoNotInterrupt() {
        listOf("native_queue_unavailable", "song_not_ready", "busy", "expired", "outcome_unknown", null).forEach {
            assertEquals(it, FailureSeverity.Warning, failureSeverity(it))
        }
    }
}
