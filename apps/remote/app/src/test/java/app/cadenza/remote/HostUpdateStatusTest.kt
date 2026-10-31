package app.cadenza.remote

import app.cadenza.remote.model.HostUpdateStatus
import app.cadenza.remote.model.hostUpdateMessage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HostUpdateStatusTest {
    @Test
    fun readyUpdatesNameTheVersionAndFailuresShowTheHostsReason() {
        assertEquals(
            "Cadenza Host 0.0.4 is ready to install.",
            hostUpdateMessage(HostUpdateStatus("ready", "0.0.4", null)),
        )
        assertEquals(
            "The repository has no compatible stable release.",
            hostUpdateMessage(HostUpdateStatus("failed", null, "The repository has no compatible stable release.")),
        )
        assertNull(hostUpdateMessage(null))
    }
}
