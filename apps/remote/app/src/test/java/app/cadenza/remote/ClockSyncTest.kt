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
import java.nio.ByteBuffer
import java.util.Base64

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
        val invite =
            JSONObject()
                .put("version", 1)
                .put("host", "192.168.1.20")
                .put("port", 43127)
                .put("fingerprint", TestCertificate.fingerprint)
                .put("certificate_der_base64", TestCertificate.encoded)
                .put("secret", "s".repeat(44))
                .put("host_name", "Example Cadenza Host")
        assertEquals(43127, Wire.invitation(invite.toString()).port)
        assertThrows(IllegalArgumentException::class.java) { Wire.invitation(invite.put("host", "https://example.com/").toString()) }
        invite.put("host", "192.168.1.20").put("fingerprint", "accept-any-certificate")
        assertThrows(IllegalArgumentException::class.java) { Wire.invitation(invite.toString()) }
    }

    @Test
    fun compactPairingPayloadDerivesThePinnedCertificateFingerprint() {
        val host = "192.168.1.20".toByteArray()
        val secret = "s".repeat(44).toByteArray()
        val certificate = TestCertificate.bytes
        val fingerprint =
            TestCertificate.fingerprint
                .chunked(2)
                .map { it.toInt(16).toByte() }
                .toByteArray()
        val payload =
            ByteBuffer
                .allocate(5 + 1 + host.size + 2 + 1 + secret.size + 2 + certificate.size + fingerprint.size)
                .put(byteArrayOf(0x43, 0x44, 0x5A, 0x50, 1))
                .put(host.size.toByte())
                .put(host)
                .putShort(43127.toShort())
                .put(secret.size.toByte())
                .put(secret)
                .putShort(certificate.size.toShort())
                .put(certificate)
                .put(fingerprint)
                .array()

        val invitation = Wire.invitation(payload)

        assertEquals("192.168.1.20", invitation.host)
        assertEquals(43127, invitation.port)
        assertEquals(TestCertificate.fingerprint, invitation.fingerprint)
        assertEquals(TestCertificate.encoded, invitation.certificateDerBase64)
        val textPayload = "CDZP:" + Base64.getUrlEncoder().withoutPadding().encodeToString(payload)
        val textInvitation = Wire.invitation(textPayload.toByteArray())
        assertEquals(invitation.host, textInvitation.host)
        assertEquals(invitation.fingerprint, textInvitation.fingerprint)
        val fingerprintOnlyPayload =
            ByteBuffer
                .allocate(5 + 1 + host.size + 2 + 1 + secret.size + fingerprint.size)
                .put(byteArrayOf(0x43, 0x44, 0x5A, 0x50, 2))
                .put(host.size.toByte())
                .put(host)
                .putShort(43127.toShort())
                .put(secret.size.toByte())
                .put(secret)
                .put(fingerprint)
                .array()
        val fingerprintOnlyInvitation = Wire.invitation(fingerprintOnlyPayload)
        assertEquals(invitation.fingerprint, fingerprintOnlyInvitation.fingerprint)
        assertEquals("", fingerprintOnlyInvitation.certificateDerBase64)
        val fingerprintOnlyText = "CDZP:" + Base64.getUrlEncoder().withoutPadding().encodeToString(fingerprintOnlyPayload)
        assertEquals(invitation.fingerprint, Wire.invitation(fingerprintOnlyText.toByteArray()).fingerprint)
        val damaged =
            payload.copyOf().also {
                it[it.lastIndex] = (it.last() + 1).toByte()
            }
        assertThrows(IllegalArgumentException::class.java) { Wire.invitation(damaged) }
    }

    @Test
    fun compactPairingIsNotRoutedThroughTheJsonFallback() {
        val payload = byteArrayOf(0x43, 0x44, 0x5A, 0x50)

        assertTrue(Wire.isCompactInvitation(payload))
        assertTrue(Wire.isCompactInvitation("CDZP:AQ".toByteArray()))
        assertFalse(Wire.isCompactInvitation("{\"version\":1}".toByteArray()))
    }
}
