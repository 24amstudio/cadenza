package app.cadenza.remote

import java.security.MessageDigest
import java.util.Base64

object TestCertificate {
    val bytes: ByteArray = requireNotNull(javaClass.getResourceAsStream("/synthetic-host.cer")).use { it.readBytes() }
    val encoded: String = Base64.getEncoder().encodeToString(bytes)
    val fingerprint: String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
}
