package app.cadenza.remote.network

import android.content.Context
import org.json.JSONObject

/** The Bluetooth path to the Host. Each [connect] starts a fresh link, so a failed one never leaves state behind. */
class BleConnection(
    private val context: Context,
    private val opened: () -> Unit,
    private val received: (JSONObject) -> Unit,
    private val closed: (String) -> Unit,
) : RemoteConnection {
    @Volatile private var transport: BleTransport? = null

    @Volatile private var stopped = false

    override fun connect() {
        if (stopped) return
        val link =
            BleTransport(
                context = context,
                opened = opened,
                received = { bytes ->
                    runCatching {
                        val frame = JSONObject(String(bytes, Charsets.UTF_8))
                        require(frame.getInt("version") == 1) { "Host and Remote versions are incompatible." }
                        received(frame)
                    }.onFailure { transport?.close(it.message ?: "The Host sent an invalid Bluetooth message.") }
                },
                closed = closed,
            )
        transport?.release()
        transport = link
        link.startScan()
    }

    override fun send(frame: JSONObject): Boolean {
        val urgent = frame.optString("type") in URGENT_FRAME_TYPES
        return transport?.send(frame.toString().toByteArray(Charsets.UTF_8), urgent) == true
    }

    override fun disconnect() {
        stopped = true
        transport?.release()
        transport = null
    }
}

// Frames the Host must answer quickly, so they go ahead of queued bulk and state frames on Bluetooth.
private val URGENT_FRAME_TYPES = setOf("hello", "pair", "clock", "command", "command.status", "operation.cancel")
