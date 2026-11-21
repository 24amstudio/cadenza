package app.cadenza.remote.network

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import kotlin.random.Random

/** Keeps both authenticated paths alive and routes bulk frames to BLE when available. */
class HybridConnection(
    context: Context,
    host: String,
    port: Int,
    opened: () -> Unit,
    received: (JSONObject) -> Unit,
    closed: (String) -> Unit,
) : RemoteConnection {
    private val onOpened = opened

    @Volatile private var lanReady = false

    @Volatile private var bleReady = false

    @Volatile private var stopped = false

    @Volatile private var bleRetries = 0

    // Set once Bluetooth has given up on its current attempt. Until then a lost Wi-Fi path does not end the session, since
    // Bluetooth may still be finding the Host.
    @Volatile private var bleFinished = false

    @Volatile private var lanRetries = 0
    private val timers = Handler(Looper.getMainLooper())
    private var openedOnce = false
    private var pendingPair: JSONObject? = null
    private var handshake: JSONObject? = null
    private val lan =
        HostConnection(host, port, ::lanOpened, received) {
            lanReady = false
            if (!bleReady && bleFinished) closed(it) else retryLanLater()
        }
    private val ble =
        BleConnection(context, ::bleOpened, received) {
            bleReady = false
            bleFinished = true
            if (!lanReady) closed(it) else retryBleLater()
        }

    // Wi-Fi may come back while Bluetooth carries the session, so the LAN path is tried again, with a growing pause.
    private fun retryLanLater() {
        if (stopped) return
        val delay = minOf(LAN_RETRY_CEILING_MS, LAN_RETRY_FLOOR_MS shl minOf(lanRetries, 4))
        lanRetries += 1
        timers.postDelayed({ if (!stopped && !lanReady) lan.connect() }, delay)
    }

    // The LAN path carries the session while Bluetooth is down, so a lost link is retried quietly and only a few times.
    // Each retry scans for a few seconds, which is not worth repeating on a Host that has Bluetooth off.
    private fun retryBleLater() {
        if (stopped || bleRetries >= BleLinkPolicy.BACKGROUND_RETRIES) return
        val delay = BleLinkPolicy.backgroundRetryDelayMs(++bleRetries, Random.nextDouble())
        timers.postDelayed({ if (!stopped && lanReady && !bleReady) ble.connect() }, delay)
    }

    private fun lanOpened() {
        lanReady = true
        lanRetries = 0
        openedOnce = true
        pendingPair?.let { pair ->
            if (lan.send(pair)) pendingPair = null
        }
        handshake?.let { lan.send(it) }
        onOpened()
    }

    private fun bleOpened() {
        bleReady = true
        bleFinished = false
        bleRetries = 0
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
        stopped = true
        timers.removeCallbacksAndMessages(null)
        lanReady = false
        bleReady = false
        lan.disconnect()
        ble.disconnect()
    }
}

private const val LAN_RETRY_FLOOR_MS = 3_000L
private const val LAN_RETRY_CEILING_MS = 30_000L
