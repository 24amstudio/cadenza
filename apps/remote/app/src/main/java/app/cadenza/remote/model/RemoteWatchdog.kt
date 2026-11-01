package app.cadenza.remote.model

import android.os.SystemClock
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Keeps a foreground Remote attached while Host recovers after an unexpected exit.
 *
 * The Remote cannot start a macOS process itself. CadenzaWatchdog on Host owns that
 * process recovery; this supervisor records the observed failure and keeps probing
 * the paired endpoint until the restarted Host accepts the connection.
 */
internal fun RemoteModel.watchdogHostUnavailable(
    message: String,
    wasConnected: Boolean,
): Job? {
    val elapsedSinceHeartbeat =
        (SystemClock.elapsedRealtime() - maxOf(lastHeartbeatAt, lastReceivedAt)).coerceAtLeast(0)
    reportLog(
        if (wasConnected) "error" else "warning",
        "watchdog.host.unavailable",
        "message=${message.take(240)} connected=$wasConnected heartbeat_age_ms=$elapsedSinceHeartbeat",
    )
    if (invitation != null || pairingPin != null ||
        (transportMode == "ble" && !wasConnected) ||
        !maintainBackgroundSessionInternal() || mutable.value.profile == null
    ) {
        return null
    }
    startDiscovery()
    reconnect?.cancel()
    return viewModelScope
        .launch {
            delay(retryDelay)
            retryDelay = (retryDelay * 2).coerceAtMost(30_000)
            connect()
        }.also { reconnect = it }
}
