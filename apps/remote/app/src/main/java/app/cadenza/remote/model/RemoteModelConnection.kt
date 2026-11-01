package app.cadenza.remote.model

import android.app.Application
import android.os.SystemClock
import androidx.lifecycle.viewModelScope
import app.cadenza.remote.data.HostProfile
import app.cadenza.remote.data.PairingInvitation
import app.cadenza.remote.data.Wire
import app.cadenza.remote.network.BleConnection
import app.cadenza.remote.network.HostConnection
import app.cadenza.remote.network.HybridConnection
import app.cadenza.remote.network.PrioritizedFrameQueue
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun RemoteModel.openConnection() {
    disconnect()
    val invite = invitation
    val profile = mutable.value.profile
    val fallback = connectionFallback(invite, profile)
    val endpoint = fallback?.let { if (invite != null) it else endpoints.next(it, SystemClock.elapsedRealtime()) }
    activeEndpoint = endpoint
    val host = endpoint?.address.orEmpty()
    val port = endpoint?.port ?: 0
    val fingerprint = invite?.fingerprint ?: profile?.fingerprint
    val version = ++generation
    clock.reset()
    lastHeartbeatAt = 0
    mutable.update { it.copy(connecting = true, connectionIssue = null) }
    connection =
        if (transportMode == "ble") {
            BleConnection(
                getApplication(),
                opened = {
                    viewModelScope.launch {
                        if (version != generation) return@launch
                        sendHandshakeChecked(invite, profile, version)
                    }
                },
                received = { frame ->
                    val accepted = frameQueue.offer(PrioritizedFrameQueue.Item(version, frame))
                    if (!accepted) {
                        viewModelScope.launch { connectionClosed(version, "Host messages arrived faster than they could be applied.") }
                    } else {
                        frameSignal.trySend(Unit)
                    }
                },
                closed = { message -> viewModelScope.launch { connectionClosed(version, message) } },
            )
        } else if (transportMode == "hybrid") {
            HybridConnection(
                getApplication(),
                host,
                port,
                requireNotNull(fingerprint),
                invite?.certificateDerBase64 ?: requireNotNull(profile).certificateDerBase64,
                opened = {
                    viewModelScope.launch {
                        if (version != generation) return@launch
                        sendHandshakeChecked(invite, profile, version)
                    }
                },
                received = { frame ->
                    val accepted = frameQueue.offer(PrioritizedFrameQueue.Item(version, frame))
                    if (!accepted) {
                        viewModelScope.launch { connectionClosed(version, "Host messages arrived faster than they could be applied.") }
                    } else {
                        frameSignal.trySend(Unit)
                    }
                },
                closed = { message -> viewModelScope.launch { connectionClosed(version, message) } },
            )
        } else {
            HostConnection(
                host,
                port,
                requireNotNull(fingerprint),
                invite?.certificateDerBase64 ?: requireNotNull(profile).certificateDerBase64,
                opened = {
                    viewModelScope.launch {
                        if (version != generation) return@launch
                        sendHandshakeChecked(invite, profile, version)
                    }
                },
                received = { frame ->
                    val accepted = frameQueue.offer(PrioritizedFrameQueue.Item(version, frame))
                    if (!accepted) {
                        viewModelScope.launch { connectionClosed(version, "Host messages arrived faster than they could be applied.") }
                    } else {
                        frameSignal.trySend(Unit)
                    }
                },
                closed = { message -> viewModelScope.launch { connectionClosed(version, message) } },
            )
        }
    connection?.connect()
    clockJob =
        viewModelScope.launch {
            delay(
                when (transportMode) {
                    "lan" -> 6_000L
                    "ble" -> 12_000L
                    else -> 20_000L
                },
            )
            if (version == generation &&
                !mutable.value.connected
            ) {
                connectionClosed(
                    version,
                    if (transportMode == "ble") {
                        "Cadenza Host did not answer over Bluetooth. Keep Bluetooth on near the Host, then try again."
                    } else {
                        "Host did not finish the connection handshake."
                    },
                )
            }
        }
}

internal suspend fun RemoteModel.sendHandshake(
    invite: PairingInvitation?,
    profile: HostProfile?,
    version: Int,
) {
    val frame = handshake.frame(invite, profile, pairingPin)
    if (version != generation) return
    frame.put("request_id", id())
    connection?.send(frame)
}

internal suspend fun RemoteModel.sendHandshakeChecked(
    invite: PairingInvitation?,
    profile: HostProfile?,
    version: Int,
) {
    try {
        sendHandshake(invite, profile, version)
    } catch (error: Exception) {
        if (version != generation) return
        showError("Pair this Remote again", error.message ?: "The saved credential could not be read.")
        disconnect()
    }
}

internal fun RemoteModel.connectionClosed(
    version: Int,
    message: String,
) {
    if (version != generation) return
    reportLog("warning", "connection.closed", message)
    activeEndpoint?.let { endpoints.failed(it, SystemClock.elapsedRealtime()) }
    val wasConnected = mutable.value.connected
    disconnect()
    mutable.update {
        it.copy(
            connected = false,
            connecting = false,
            connectionIssue = message,
            searching = false,
            preparing = false,
            lyricsLoading = false,
        )
    }
    clockJob?.cancel()
    if (invitation != null || pairingPin != null) {
        showError("Could not pair", message)
        return
    }
    if (transportMode == "ble" && !wasConnected) {
        showError("Could not connect over Bluetooth", message)
        return
    }
    watchdogHostUnavailable(message, wasConnected)
}

internal fun RemoteModel.pingClock() {
    lastClockSentAt = SystemClock.elapsedRealtime()
    connection?.send(
        Wire
            .frame("clock")
            .put("request_id", id())
            .put("clock", JSONObject().put("sent_at_remote_ms", SystemClock.elapsedRealtime())),
    )
}
