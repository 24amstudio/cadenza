package app.cadenza.remote.data

import kotlin.math.abs

class ClockSync {
    private data class Sample(
        val offset: Long,
        val uncertainty: Long,
    )

    private val samples = ArrayDeque<Sample>()
    var offsetMs: Long = 0
        private set
    var uncertaintyMs: Long = Long.MAX_VALUE
        private set

    val ready: Boolean get() = samples.size >= 3 && uncertaintyMs <= 250

    fun reset() {
        samples.clear()
        offsetMs = 0
        uncertaintyMs = Long.MAX_VALUE
    }

    fun observe(
        sentRemote: Long,
        receivedHost: Long,
        sentHost: Long,
        receivedRemote: Long,
    ) {
        if (listOf(sentRemote, receivedHost, sentHost, receivedRemote).any { it !in 0..Wire.MAXIMUM_COUNTER }) return
        val roundTrip = (receivedRemote - sentRemote) - (sentHost - receivedHost)
        if (sentRemote < 0 || receivedRemote < sentRemote || sentHost < receivedHost || roundTrip !in 0..2_000) return
        val offset = ((receivedHost - sentRemote) + (sentHost - receivedRemote)) / 2
        if (samples.isNotEmpty() && abs(offset - offsetMs) > 2_000) reset()
        samples.addLast(Sample(offset, (roundTrip + 1) / 2))
        if (samples.size > 12) samples.removeFirst()
        val best = samples.minBy { it.uncertainty }
        offsetMs = best.offset
        uncertaintyMs = best.uncertainty
    }

    fun hostTime(remoteNow: Long): Long = remoteNow + offsetMs

    fun deadline(remoteNow: Long): Long {
        check(ready) { "Clock synchronization is not ready. Wait a moment and retry." }
        return hostTime(remoteNow) + 900 - uncertaintyMs
    }

    fun position(
        snapshot: HostSnapshot,
        remoteNow: Long,
        stale: Boolean,
    ): Long {
        val current = snapshot.current ?: return 0
        val elapsed =
            if (snapshot.playing && ready) {
                (hostTime(remoteNow) - current.sampledAtHostMs).coerceIn(0, if (stale) 2_500 else Long.MAX_VALUE)
            } else {
                0
            }
        val position = current.positionMs + elapsed
        return current.song.durationMs?.let { position.coerceIn(0, it) } ?: position.coerceAtLeast(0)
    }
}
