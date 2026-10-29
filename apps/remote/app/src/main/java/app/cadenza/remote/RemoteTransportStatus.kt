package app.cadenza.remote

import android.os.SystemClock
import app.cadenza.remote.data.EffectiveTransportDecision
import app.cadenza.remote.data.TransportPathStatus
import kotlinx.coroutines.flow.update
import org.json.JSONObject

internal fun RemoteModel.applySessionStatus(value: JSONObject) {
    val effective = value.optJSONObject("effective") ?: return
    val selected = effective.optString("selected").takeIf { it.isNotBlank() && it != "null" }
    val decision =
        EffectiveTransportDecision(
            selected = selected,
            bulk = effective.optString("bulk").takeIf { it.isNotBlank() && it != "null" },
            reason = effective.optString("reason", "Host selected the active transport."),
            hostPreference = effective.optString("host_preference", "balanced"),
            remotePreference = effective.optString("remote_preference").takeIf { it.isNotBlank() && it != "null" },
            policyMode = effective.optString("policy_mode", "balanced_negotiation"),
            confidence = effective.optString("confidence", "low"),
        )
    mutable.update { it.copy(effectiveTransport = decision) }
    val desired =
        when (selected) {
            "ble" -> "ble"
            "lan", "wifi", "ethernet" -> "lan"
            else -> null
        }
    if (desired != null && transportMode != "hybrid" && desired != transportMode) {
        transportMode = desired
        preferences.write("transport_mode" to desired)
        connect()
    }
}

internal fun RemoteModel.publishStatus() {
    if (!mutable.value.connected) return
    val measured =
        pathMeasurements.statuses(SystemClock.elapsedRealtime()).ifEmpty {
            listOf(
                TransportPathStatus(
                    transport = if (transportMode == "ble") "ble" else "lan",
                    state = "connected",
                    rssiDbm = null,
                    rttMs = null,
                    lossPercent = null,
                    throughputKbps = null,
                    backlogBytes = 0,
                ),
            )
        }
    connection?.send(statusPublisher.frame(preference = transportPreference, paths = measured))
    lastStatusSentAt = SystemClock.elapsedRealtime()
}
