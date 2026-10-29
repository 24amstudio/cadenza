package app.cadenza.remote.network

import android.content.Context
import org.json.JSONObject

class BleConnection(
    context: Context,
    private val opened: () -> Unit,
    private val received: (JSONObject) -> Unit,
    private val closed: (String) -> Unit,
) : RemoteConnection {
    private val transport =
        BleTransport(
            context = context,
            opened = opened,
            received = { bytes ->
                runCatching {
                    val frame = JSONObject(String(bytes, Charsets.UTF_8))
                    require(frame.getInt("version") == 1) { "Host and Remote versions are incompatible." }
                    received(frame)
                }.onFailure { closed(it.message ?: "The Host sent an invalid Bluetooth message.") }
            },
            closed = closed,
        )

    override fun connect() = transport.startScan()

    override fun send(frame: JSONObject): Boolean = transport.send(frame.toString().toByteArray(Charsets.UTF_8))

    override fun disconnect() = transport.close("Remote closed Bluetooth connection.")
}
