package app.cadenza.remote

import app.cadenza.remote.data.ClockSync
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.counter
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ClockSyncTest {
    @Test
    fun clockNeedsRepeatedSamplesAndUsesTheSmallestMeasuredUncertainty() {
        val clock = ClockSync()
        assertThrows(IllegalStateException::class.java) { clock.deadline(1_000) }
        clock.observe(1_000, 1_510, 1_510, 1_020)
        clock.observe(2_000, 2_600, 2_600, 2_200)
        assertFalse(clock.ready)
        clock.observe(3_000, 3_510, 3_510, 3_020)
        assertTrue(clock.ready)
        assertEquals(500L, clock.offsetMs)
        assertEquals(10L, clock.uncertaintyMs)
        assertEquals(5_390L, clock.deadline(4_000))
        clock.observe(5_000, 50_010, 50_010, 5_020)
        assertFalse(clock.ready)
    }

    @Test
    fun protocolCountersRejectTruncationAndStringCoercion() {
        assertEquals(5L, JSONObject("{\"sequence\":5}").counter("sequence"))
        assertThrows(ArithmeticException::class.java) { JSONObject("{\"sequence\":5.5}").counter("sequence") }
        assertThrows(IllegalArgumentException::class.java) { JSONObject("{\"sequence\":\"5\"}").counter("sequence") }
        assertThrows(IllegalArgumentException::class.java) { JSONObject("{\"sequence\":true}").counter("sequence") }
        assertThrows(IllegalArgumentException::class.java) { JSONObject().put("sequence", Wire.MAXIMUM_COUNTER + 1).counter("sequence") }
    }

    @Test
    fun invalidPairingDetailsCannotConstructAConnectionTarget() {
        val invite =
            JSONObject()
                .put("version", 1)
                .put("host", "192.168.1.20")
                .put("port", 43127)
                .put("fingerprint", TestCertificate.fingerprint)
                .put("certificate_der_base64", TestCertificate.encoded)
                .put("secret", "s".repeat(44))
                .put("host_name", "Example Mac")
        assertEquals(43127, Wire.invitation(invite.toString()).port)
        assertThrows(IllegalArgumentException::class.java) { Wire.invitation(invite.put("host", "https://example.com/").toString()) }
        invite.put("host", "192.168.1.20").put("fingerprint", "accept-any-certificate")
        assertThrows(IllegalArgumentException::class.java) { Wire.invitation(invite.toString()) }
    }
}
