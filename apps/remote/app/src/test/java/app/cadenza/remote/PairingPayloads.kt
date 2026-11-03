package app.cadenza.remote

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Base64

/** Encodes native invitations the way Cadenza Host does: "CDZP", version byte, host, control port, and one-use secret. */
internal object PairingPayloads {
    fun binary(
        host: String = "192.168.1.20",
        port: Int = 43127,
        secret: String = "s".repeat(44),
        version: Byte = 3,
    ): ByteArray {
        val address = host.toByteArray()
        val pairingSecret = secret.toByteArray()
        return ByteBuffer
            .allocate(4 + 1 + 1 + address.size + 2 + 1 + pairingSecret.size)
            .order(ByteOrder.BIG_ENDIAN)
            .put(byteArrayOf(0x43, 0x44, 0x5A, 0x50))
            .put(version)
            .put(address.size.toByte())
            .put(address)
            .putShort(port.toShort())
            .put(pairingSecret.size.toByte())
            .put(pairingSecret)
            .array()
    }

    fun text(payload: ByteArray): String = "CDZP:" + Base64.getUrlEncoder().withoutPadding().encodeToString(payload)
}
