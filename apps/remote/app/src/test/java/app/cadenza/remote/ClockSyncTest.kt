package app.cadenza.remote

import app.cadenza.remote.data.ClockSync
import app.cadenza.remote.data.CurrentPlayback
import app.cadenza.remote.data.HostSnapshot
import app.cadenza.remote.data.Song
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
    fun positionExtrapolatesAfterFirstSampleBeforeClockIsFullyReady() {
        val clock = ClockSync()
        clock.observe(1_000, 1_510, 1_510, 1_020)
        val snapshot =
            HostSnapshot(
                hostId = "host",
                hostEpoch = "epoch",
                revision = 1,
                sequence = 1,
                hostTimeMs = 1_510,
                allowCrossRemoteEdits = true,
                playing = true,
                volume = 50,
                current =
                    CurrentPlayback(
                        occurrenceId = "occurrence",
                        entryId = null,
                        requestedBy = null,
                        requesterName = "Host",
                        song = Song("apple_music", "song", "Title", "Artist", durationMs = 60_000),
                        positionMs = 5_000,
                        sampledAtHostMs = 1_510,
                    ),
                queue = emptyList(),
                totalRemainingMs = null,
                quality = "unknown",
                incoming = null,
                mixing = null,
                synchronized = true,
                issue = null,
                observationGap = false,
            )

        assertEquals(5_500L, clock.position(snapshot, 1_510, stale = false))
        assertFalse(clock.ready)
    }

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
        assertEquals(43127, Wire.invitation(PairingPayloads.binary()).port)
        assertThrows(IllegalArgumentException::class.java) {
            Wire.invitation(PairingPayloads.binary(host = "https://example.com/"))
        }
        assertThrows(IllegalArgumentException::class.java) { Wire.invitation(PairingPayloads.binary(port = 80)) }
        assertThrows(IllegalArgumentException::class.java) { Wire.invitation(PairingPayloads.binary(secret = "short")) }
        assertThrows(IllegalArgumentException::class.java) { Wire.invitation(PairingPayloads.binary(version = 2)) }
    }

    @Test
    fun compactPairingPayloadCarriesTheHostTargetAndSecret() {
        val payload = PairingPayloads.binary()

        val invitation = Wire.invitation(payload)

        assertEquals("192.168.1.20", invitation.host)
        assertEquals(43127, invitation.port)
        assertEquals("s".repeat(44), invitation.secret)
        assertEquals(invitation.secret, Wire.invitation(PairingPayloads.text(payload).toByteArray()).secret)
        assertThrows(IllegalArgumentException::class.java) { Wire.invitation(payload.copyOf(payload.size - 3)) }
        assertThrows(IllegalArgumentException::class.java) { Wire.invitation(payload + byteArrayOf(0)) }
    }

    @Test
    fun legacyJsonInvitationsAreRejected() {
        val legacy = "{\"version\":1,\"host\":\"192.168.1.20\",\"port\":43127,\"secret\":\"${"s".repeat(44)}\"}"

        assertThrows(IllegalArgumentException::class.java) { Wire.invitation(legacy.toByteArray()) }
    }
}
