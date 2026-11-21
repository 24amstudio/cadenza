package app.cadenza.remote.network

/**
 * How long a Remote waits on a quiet Host before it acts. The Host sends a state or heartbeat at least every 2 s over
 * the LAN, and every 5 s while playing or 15 s while paused over Bluetooth, so each limit allows about two missed frames.
 * Only a LAN-only session keeps the short limits. A hybrid session may be running on Bluetooth alone.
 */
internal object HostLivenessPolicy {
    private const val LAN_SILENCE_MS = 10_000L
    private const val BLUETOOTH_SILENCE_MS = 35_000L
    private const val LAN_STALE_MS = 3_000L
    private const val BLUETOOTH_STALE_MS = 20_000L

    /** Silence after which the Host's playback is assumed interrupted and its session notification is dismissed. */
    const val SESSION_INTERRUPTED_MS = 5 * 60_000L

    /** Silence after which the Host counts as gone and the Remote reconnects. */
    fun silenceLimitMs(transportMode: String): Long = if (transportMode == "lan") LAN_SILENCE_MS else BLUETOOTH_SILENCE_MS

    /** Time since the last state or heartbeat after which what the Remote shows is no longer current. */
    fun staleAfterMs(transportMode: String): Long = if (transportMode == "lan") LAN_STALE_MS else BLUETOOTH_STALE_MS
}
