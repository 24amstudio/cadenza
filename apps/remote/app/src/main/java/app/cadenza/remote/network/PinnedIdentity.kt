package app.cadenza.remote.network

import java.io.ByteArrayInputStream
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.Base64
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

class PinnedIdentity(
    encodedCertificate: String,
    fingerprint: String,
) {
    val certificate: X509Certificate
    val trustManager: X509TrustManager
    val socketFactory: SSLSocketFactory
    private val expected: ByteArray

    init {
        require(fingerprint.matches(Regex("[0-9a-f]{64}"))) { "Invalid Host certificate fingerprint." }
        require(encodedCertificate.length in 512..3_072) { "Pair again using a current Cadenza Host QR code." }
        expected = fingerprint.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val encoded = Base64.getDecoder().decode(encodedCertificate)
        certificate = CertificateFactory.getInstance("X.509").generateCertificate(ByteArrayInputStream(encoded)) as X509Certificate
        require(encoded.contentEquals(certificate.encoded) && matches(certificate)) {
            "The public certificate does not match the pairing fingerprint."
        }
        certificate.checkValidity()
        val anchors =
            KeyStore.getInstance(KeyStore.getDefaultType()).apply {
                load(null, null)
                setCertificateEntry("Cadenza Host", certificate)
            }
        trustManager =
            TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).run {
                init(anchors)
                trustManagers.filterIsInstance<X509TrustManager>().single()
            }
        socketFactory =
            SSLContext
                .getInstance("TLS")
                .apply {
                    init(null, arrayOf(trustManager), SecureRandom())
                }.socketFactory
    }

    fun matches(leaf: X509Certificate?): Boolean =
        leaf != null && MessageDigest.isEqual(expected, MessageDigest.getInstance("SHA-256").digest(leaf.encoded))
}
