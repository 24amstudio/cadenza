package app.cadenza.remote

import app.cadenza.remote.network.PinnedIdentity
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class PinnedIdentityTest {
    @Test
    fun aMatchingPublicCertificateUsesThePlatformsTrustValidation() {
        val identity = PinnedIdentity(TestCertificate.encoded, TestCertificate.fingerprint)
        identity.trustManager.checkServerTrusted(arrayOf(identity.certificate), "RSA")
        assertTrue(identity.matches(identity.certificate))
        assertFalse(identity.matches(null))
    }

    @Test
    fun discoveryOrAnUnmatchedCertificateCannotEstablishTrust() {
        assertThrows(IllegalArgumentException::class.java) { PinnedIdentity(TestCertificate.encoded, "0".repeat(64)) }
        assertThrows(IllegalArgumentException::class.java) { PinnedIdentity("", TestCertificate.fingerprint) }
    }
}
