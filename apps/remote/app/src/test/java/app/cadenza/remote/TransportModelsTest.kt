package app.cadenza.remote

import app.cadenza.remote.data.SessionStatus
import app.cadenza.remote.data.TransportPathStatus
import app.cadenza.remote.data.TransportPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class TransportModelsTest {
    @Test
    fun acceptsHybridPolicyAndBoundedPathStatus() {
        val policy = TransportPolicy("hybrid", "deterministic", "ble", "lan")
        val status =
            SessionStatus(
                reportedAtMs = 10,
                device = "remote",
                power = null,
                resources = null,
                paths = listOf(TransportPathStatus("ble", "connected", -58, 18, 0.2, 96, 0)),
            )

        assertEquals("hybrid", policy.mode)
        assertEquals(-58, status.paths.single().rssiDbm)
    }

    @Test
    fun rejectsInvalidTransportValues() {
        assertThrows(IllegalArgumentException::class.java) {
            TransportPolicy("wifi_only", "deterministic", null, null)
        }
        assertThrows(IllegalArgumentException::class.java) {
            TransportPathStatus("ble", "connected", -128, null, null, null, null)
        }
    }
}
