package app.cadenza.remote.ui

import app.cadenza.remote.data.TransportPathStatus

/** Signal bars for the link to Cadenza Host, out of four. Same thresholds as the web Remote's sidebar. */
internal const val SIGNAL_BAR_COUNT = 4

internal fun linkSignalBars(
    connected: Boolean,
    paths: List<TransportPathStatus>,
): Int {
    if (!connected) return 0
    val live = paths.filter { it.state == "connected" || it.state == "degraded" }
    val roundTrip = live.mapNotNull { it.rttMs }.minOrNull() ?: return 1
    return when {
        roundTrip <= 80 -> 4
        roundTrip <= 200 -> 3
        roundTrip <= 500 -> 2
        else -> 1
    }
}
