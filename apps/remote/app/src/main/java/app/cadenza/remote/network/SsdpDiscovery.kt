package app.cadenza.remote.network

import android.os.Handler
import android.os.Looper
import app.cadenza.remote.model.id
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Optional LAN discovery fallback. Results are hints and never establish trust. */
class SsdpDiscovery(
    private val found: (DiscoveredHost) -> Unit,
) : AutoCloseable {
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())

    @Volatile private var running = false
    private var socket: DatagramSocket? = null

    fun start() {
        if (running) return
        running = true
        executor.execute {
            val request =
                (
                    "M-SEARCH * HTTP/1.1\r\n" +
                        "HOST: 239.255.255.250:1900\r\n" +
                        "MAN: \"ssdp:discover\"\r\n" +
                        "MX: 1\r\n" +
                        "ST: urn:cadenza:host:1\r\n\r\n"
                ).toByteArray()
            runCatching {
                DatagramSocket().use { current ->
                    socket = current
                    current.soTimeout = 1_500
                    current.send(DatagramPacket(request, request.size, InetAddress.getByName("239.255.255.250"), 1900))
                    val bytes = ByteArray(2048)
                    while (running) {
                        val packet = DatagramPacket(bytes, bytes.size)
                        try {
                            current.receive(packet)
                        } catch (_: Exception) {
                            break
                        }
                        parse(packet.data, packet.length)?.let { host -> handler.post { if (running) found(host) } }
                    }
                }
            }
            socket = null
        }
    }

    private fun parse(
        bytes: ByteArray,
        length: Int,
    ): DiscoveredHost? {
        val headers =
            bytes
                .copyOf(length)
                .toString(Charsets.US_ASCII)
                .lineSequence()
                .mapNotNull { line -> line.split(":", limit = 2).takeIf { it.size == 2 } }
                .associate { it[0].trim().lowercase() to it[1].trim() }
        val hostId = headers["host-id"] ?: return null
        val location = headers["location"] ?: return null
        val uri = runCatching { java.net.URI(location) }.getOrNull() ?: return null
        val address = uri.host ?: return null
        val port = if (uri.port in 1024..65535) uri.port else return null
        if (!hostId.matches(Regex("[0-9a-f-]{36}"))) return null
        return DiscoveredHost(hostId, address, port)
    }

    override fun close() {
        running = false
        socket?.close()
        executor.shutdownNow()
        executor.awaitTermination(1, TimeUnit.SECONDS)
    }
}
