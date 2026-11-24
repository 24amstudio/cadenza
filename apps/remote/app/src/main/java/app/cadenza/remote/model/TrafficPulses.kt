package app.cadenza.remote.model

import android.os.SystemClock
import app.cadenza.remote.network.RemoteConnection
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import org.json.JSONObject

/**
 * Counts frames in each direction for the link indicator. A direction pulses at most once per [INTERVAL_MS], so a burst
 * of frames flashes its arrow once and no timer runs per frame.
 */
class TrafficPulses(
    private val clock: () -> Long = SystemClock::elapsedRealtime,
) {
    private val incomingCount = MutableStateFlow(0L)
    private val outgoingCount = MutableStateFlow(0L)
    private var lastIncoming: Long? = null
    private var lastOutgoing: Long? = null

    val incoming: StateFlow<Long> = incomingCount.asStateFlow()
    val outgoing: StateFlow<Long> = outgoingCount.asStateFlow()

    fun received() {
        val now = clock()
        if (!due(lastIncoming, now)) return
        lastIncoming = now
        incomingCount.update { it + 1 }
    }

    fun sent() {
        val now = clock()
        if (!due(lastOutgoing, now)) return
        lastOutgoing = now
        outgoingCount.update { it + 1 }
    }

    // A first pulse is always due, so no clock value needs a sentinel that subtraction could overflow.
    private fun due(
        last: Long?,
        now: Long,
    ) = last == null || now - last >= INTERVAL_MS

    companion object {
        const val INTERVAL_MS = 100L
    }
}

/** Passes every frame through and records the ones that were accepted for sending. */
internal class MeteredConnection(
    private val inner: RemoteConnection,
    private val pulses: TrafficPulses,
) : RemoteConnection {
    override fun connect() = inner.connect()

    override fun send(frame: JSONObject): Boolean = inner.send(frame).also { if (it) pulses.sent() }

    override fun disconnect() = inner.disconnect()
}
