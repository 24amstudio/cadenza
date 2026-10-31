package app.cadenza.remote.network

import android.content.Context
import org.json.JSONObject

/** Keeps both authenticated paths alive and routes bulk frames to BLE when available. */
class HybridConnection(
    context: Context,
    host: String,
    port: Int,
    fingerprint: String,
    certificateDerBase64: String,
    opened: () -> Unit,
    received: (JSONObject) -> Unit,
    closed: (String) -> Unit,
) : RemoteConnection {
    private val onOpened = opened
    private var lanReady = false
    private var bleReady = false
    private var openedOnce = false
    private var pendingPair: JSONObject? = null
    private var handshake: JSONObject? = null
    private val lan =
        HostConnection(host, port, fingerprint, certificateDerBase64, ::lanOpened, received) {
            lanReady = false
            if (!bleReady) closed(it)
        }
    private val ble =
        BleConnection(context, ::bleOpened, received) {
            bleReady = false
            if (!lanReady) closed(it)
        }

    private fun lanOpened() {
        lanReady = true
        openedOnce = true
        pendingPair?.let { pair ->
            if (lan.send(pair)) pendingPair = null
        }
        handshake?.let { lan.send(it) }
        onOpened()
    }

    private fun bleOpened() {
        bleReady = true
        handshake?.let { ble.send(it) }
        if (!openedOnce) {
            openedOnce = true
            onOpened()
        }
    }

    override fun connect() {
        lan.connect()
        ble.connect()
    }

    override fun send(frame: JSONObject): Boolean {
        val type = frame.optString("type")
        if (type == "pair") {
            pendingPair = frame
            if (!lanReady) return false
            val sent = lan.send(frame)
            if (sent) pendingPair = null
            return sent
        }
        if (type == "hello") {
            handshake = frame
            val lanSent = lanReady && lan.send(frame)
            val bleSent = bleReady && ble.send(frame)
            return lanSent || bleSent
        }
        val bulk = type == "artwork.get" || type == "lyrics.get" || type == "search" || type == "search.suggest" || type == "song.prepare"
        val preferred = if (bulk) ble else lan
        val fallback = if (bulk) lan else ble
        return (if (if (bulk) bleReady else lanReady) preferred.send(frame) else false) ||
            (if (if (bulk) lanReady else bleReady) fallback.send(frame) else false)
    }

    override fun disconnect() {
        lanReady = false
        bleReady = false
        lan.disconnect()
        ble.disconnect()
    }
}
