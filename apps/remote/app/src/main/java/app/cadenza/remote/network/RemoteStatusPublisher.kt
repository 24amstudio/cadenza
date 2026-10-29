package app.cadenza.remote.network

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.SystemClock
import app.cadenza.remote.data.TransportConstraints
import app.cadenza.remote.data.TransportPathStatus
import org.json.JSONArray
import org.json.JSONObject

class RemoteStatusPublisher(
    private val context: Context,
) {
    fun frame(
        preference: String = "balanced",
        constraints: TransportConstraints = TransportConstraints(),
        paths: List<TransportPathStatus> =
            listOf(
                TransportPathStatus("lan", "connected", null, null, null, null, 0),
            ),
    ): JSONObject {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN)
        val power = JSONObject()
        if (level >= 0 && scale > 0) {
            power.put("battery_percent", (level * 100 / scale).coerceIn(0, 100))
        }
        power.put(
            "charging",
            status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL,
        )
        power.put("source", powerSource(battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0))
        return JSONObject()
            .put("version", 1)
            .put("type", "session.status")
            .put(
                "status",
                JSONObject()
                    .put("reported_at_ms", SystemClock.elapsedRealtime())
                    .put("device", "remote")
                    .put("preference", preference)
                    .put(
                        "constraints",
                        JSONObject()
                            .put("maximum_latency_ms", constraints.maximumLatencyMs)
                            .put("maximum_loss_percent", constraints.maximumLossPercent)
                            .put("require_reliable", constraints.requireReliable)
                            .put("minimum_reliability_percent", constraints.minimumReliabilityPercent),
                    ).put("power", power)
                    .put("paths", JSONArray(paths.map(::pathJson))),
            )
    }

    private fun pathJson(path: TransportPathStatus): JSONObject =
        JSONObject()
            .put("transport", path.transport)
            .put("state", path.state)
            .apply {
                path.rssiDbm?.let { put("rssi_dbm", it) }
                path.rttMs?.let { put("rtt_ms", it) }
                path.lossPercent?.let { put("loss_percent", it) }
                path.throughputKbps?.let { put("throughput_kbps", it) }
                path.backlogBytes?.let { put("backlog_bytes", it) }
                path.energyPercentPerHour?.let { put("energy_percent_per_hour", it) }
                path.energyConfidence?.let { put("energy_confidence", it) }
                path.sampleAgeMs?.let { put("sample_age_ms", it) }
                path.p95RttMs?.let { put("p95_rtt_ms", it) }
                path.reconnects?.let { put("reconnects", it) }
                path.activeRemotes?.let { put("active_remotes", it) }
            }

    private fun powerSource(plugged: Int): String =
        when (plugged) {
            BatteryManager.BATTERY_PLUGGED_AC -> "ac"
            BatteryManager.BATTERY_PLUGGED_USB -> "usb"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
            else -> "battery"
        }
}
