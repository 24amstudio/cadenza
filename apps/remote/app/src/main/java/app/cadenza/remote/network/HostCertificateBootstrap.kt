package app.cadenza.remote.network

import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.security.cert.CertificateFactory
import java.util.Base64

object HostCertificateBootstrap {
    private val magic = byteArrayOf(0x43, 0x44, 0x5A, 0x42)

    fun port(controlPort: Int): Int = if (controlPort == 65_535) controlPort - 1 else controlPort + 1

    fun fetch(
        host: String,
        controlPort: Int,
        secret: String,
    ): String {
        val bootstrapPort = port(controlPort)
        require(bootstrapPort in 1024..65_535) { "The Host pairing bootstrap port is invalid." }
        val addresses =
            InetAddress.getAllByName(host).filter { address ->
                address.isSiteLocalAddress || address.isLinkLocalAddress || address.isLoopbackAddress
            }
        require(addresses.isNotEmpty()) { "Cadenza Host must be on the local network." }
        val secretBytes = secret.toByteArray(Charsets.UTF_8)
        require(secretBytes.size in 32..128) { "The Host pairing secret is invalid." }
        var lastError: Exception? = null
        for (address in addresses) {
            try {
                return fetch(address, bootstrapPort, secretBytes)
            } catch (error: Exception) {
                lastError = error
            }
        }
        throw lastError ?: IllegalStateException("Could not retrieve the Host certificate.")
    }

    private fun fetch(
        address: InetAddress,
        port: Int,
        secret: ByteArray,
    ): String {
        Socket().use { socket ->
            socket.connect(InetSocketAddress(address, port), 1_500)
            socket.soTimeout = 2_500
            val output = DataOutputStream(socket.getOutputStream())
            output.write(magic)
            output.writeByte(1)
            output.writeByte(secret.size)
            output.write(secret)
            output.flush()
            val input = DataInputStream(socket.getInputStream())
            val responseMagic = ByteArray(magic.size)
            input.readFully(responseMagic)
            require(responseMagic.contentEquals(magic)) { "The Host pairing bootstrap response is invalid." }
            require(input.readUnsignedByte() == 1) { "The Host pairing bootstrap version is unsupported." }
            val certificateLength = input.readUnsignedShort()
            require(certificateLength in 512..3_072) { "The Host certificate is invalid." }
            val certificate = ByteArray(certificateLength)
            input.readFully(certificate)
            CertificateFactory
                .getInstance("X.509")
                .generateCertificate(ByteArrayInputStream(certificate))
            return Base64.getEncoder().encodeToString(certificate)
        }
    }
}
