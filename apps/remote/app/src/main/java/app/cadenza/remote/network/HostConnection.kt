package app.cadenza.remote.network

import app.cadenza.remote.data.Wire
import okhttp3.Dns
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.net.UnknownHostException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit

class HostConnection(
    host: String,
    port: Int,
    fingerprint: String,
    certificateDerBase64: String,
    private val opened: () -> Unit,
    private val received: (JSONObject) -> Unit,
    private val closed: (String) -> Unit,
) : WebSocketListener() {
    private val identity = PinnedIdentity(certificateDerBase64, fingerprint)
    private val client =
        OkHttpClient
            .Builder()
            .sslSocketFactory(identity.socketFactory, identity.trustManager)
            .hostnameVerifier { hostname, session ->
                hostname.equals(host, ignoreCase = true) &&
                    runCatching {
                        identity.matches(session.peerCertificates.firstOrNull() as? X509Certificate)
                    }.getOrDefault(false)
            }.dns { hostname ->
                Dns.SYSTEM
                    .lookup(hostname)
                    .filter {
                        it.isSiteLocalAddress || it.isLinkLocalAddress || it.isLoopbackAddress
                    }.ifEmpty { throw UnknownHostException("Cadenza Host must be on the local network.") }
            }.connectTimeout(5, TimeUnit.SECONDS)
            .callTimeout(5, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .writeTimeout(1, TimeUnit.SECONDS)
            .pingInterval(10, TimeUnit.SECONDS)
            .followRedirects(false)
            .followSslRedirects(false)
            .build()
    private val address =
        okhttp3.HttpUrl
            .Builder()
            .scheme("https")
            .host(host)
            .port(port)
            .encodedPath("/")
            .build()
    private var socket: WebSocket? = null

    @Volatile private var stopped = false

    fun connect() {
        socket = client.newWebSocket(Request.Builder().url(address).build(), this)
    }

    fun send(frame: JSONObject): Boolean {
        val data = frame.toString()
        require(data.toByteArray().size <= Wire.MAXIMUM_BYTES) { "The control message is too large." }
        return socket?.send(data) == true
    }

    fun disconnect() {
        stopped = true
        socket?.close(1000, "Remote closed")
        socket?.cancel()
        client.connectionPool.evictAll()
        client.dispatcher.executorService.shutdown()
    }

    override fun onOpen(
        webSocket: WebSocket,
        response: Response,
    ) {
        if (!stopped) opened()
    }

    override fun onMessage(
        webSocket: WebSocket,
        text: String,
    ) {
        if (stopped) return
        if (text.toByteArray().size > Wire.MAXIMUM_BYTES) {
            webSocket.close(1009, "Message too large")
            return
        }
        try {
            val frame = JSONObject(text)
            require(frame.getInt("version") == 1) { "Host and Remote versions are incompatible." }
            received(frame)
        } catch (error: Exception) {
            webSocket.close(1007, "Invalid message")
            closed(error.message ?: "The Host sent an invalid message.")
        }
    }

    override fun onClosed(
        webSocket: WebSocket,
        code: Int,
        reason: String,
    ) {
        if (!stopped) closed("Disconnected from Cadenza Host.")
    }

    override fun onFailure(
        webSocket: WebSocket,
        t: Throwable,
        response: Response?,
    ) {
        if (!stopped) closed(t.message ?: "Could not reach Cadenza Host.")
    }
}
