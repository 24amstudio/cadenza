package app.cadenza.remote

import android.os.SystemClock
import app.cadenza.remote.data.EffectiveTransportDecision
import app.cadenza.remote.data.TransportPathStatus
import kotlinx.coroutines.flow.update
import org.json.JSONObject

internal fun RemoteModel.applySessionStatus(value: JSONObject) {
    val paths = parseTransportPaths(value.optJSONArray("paths"))
    val effective = value.optJSONObject("effective")
    if (effective == null) {
        mutable.update { it.copy(transportPaths = paths) }
        return
    }
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
    mutable.update { it.copy(effectiveTransport = decision, transportPaths = paths) }
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

internal fun parseTransportPaths(array: org.json.JSONArray?): List<TransportPathStatus> {
    if (array == null) return emptyList()
    return buildList {
        for (index in 0 until array.length()) {
            if (size == 4) break
            val path = array.optJSONObject(index) ?: continue
            val transport = path.optString("transport")
            val state = path.optString("state")
            if (transport !in setOf("lan", "wifi", "ethernet", "ble") ||
                state !in setOf("connected", "connecting", "degraded", "disconnected")
            ) {
                continue
            }
            runCatching {
                TransportPathStatus(
                    transport = transport,
                    state = state,
                    rssiDbm = path.optionalInt("rssi_dbm")?.takeIf { it in -127..0 },
                    rttMs = path.optionalLong("rtt_ms"),
                    lossPercent = path.optionalDouble("loss_percent")?.takeIf { it in 0.0..100.0 },
                    throughputKbps = path.optionalLong("throughput_kbps"),
                    backlogBytes = path.optionalLong("backlog_bytes"),
                    energyPercentPerHour = path.optionalDouble("energy_percent_per_hour")?.takeIf { it >= 0.0 },
                    energyConfidence =
                        path.optString("energy_confidence").takeIf { it in setOf("low", "medium", "high") },
                    sampleAgeMs = path.optionalLong("sample_age_ms"),
                    p95RttMs = path.optionalLong("p95_rtt_ms"),
                    reconnects = path.optionalLong("reconnects"),
                    activeRemotes = path.optionalLong("active_remotes"),
                )
            }.getOrNull()?.let(::add)
        }
    }
}

private fun JSONObject.optionalInt(key: String): Int? = (opt(key) as? Number)?.toInt()

private fun JSONObject.optionalLong(key: String): Long? = (opt(key) as? Number)?.toLong()

private fun JSONObject.optionalDouble(key: String): Double? = (opt(key) as? Number)?.toDouble()?.takeIf(Double::isFinite)

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
