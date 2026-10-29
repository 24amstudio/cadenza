package app.cadenza.remote.network

import app.cadenza.remote.data.TransportPathStatus
import app.cadenza.remote.data.TransportPolicy

class TransportPathSelector {
    private var selected: String? = null

    fun chooseMeasured(
        policy: TransportPolicy,
        paths: List<TransportPathStatus>,
        preference: PathPreference,
    ): TransportPathStatus? {
        val eligible =
            paths
                .filter { it.state == "connected" || it.state == "degraded" }
                .filter { allowed(policy.mode, it.transport) }
        val candidate = eligible.maxByOrNull { measuredScore(it, preference) } ?: return null
        val current = eligible.firstOrNull { it.transport == selected }
        if (current != null && measuredScore(current, preference) >= measuredScore(candidate, preference) - 0.08) {
            return current
        }
        selected = candidate.transport
        return candidate
    }

    fun choose(
        policy: TransportPolicy,
        paths: List<TransportPathStatus>,
    ): TransportPathStatus? {
        val eligible =
            paths
                .filter { it.state == "connected" || it.state == "degraded" }
                .filter { allowed(policy.mode, it.transport) }
        if (eligible.isEmpty()) return null
        return if (policy.selection == "deterministic") {
            val comparator =
                compareBy<TransportPathStatus> { primaryRank(policy.primary, it.transport) }
                    .thenBy { healthRank(it.state) }
                    .thenBy { it.rttMs ?: Long.MAX_VALUE }
                    .thenBy { stableRank(it.transport) }
            eligible.minWith(comparator)
        } else {
            val comparator =
                compareBy<TransportPathStatus> { score(it) }
                    .thenByDescending { it.throughputKbps ?: 0 }
                    .thenBy { stableRank(it.transport) }
            eligible.maxWith(comparator)
        }
    }

    private fun allowed(
        mode: String,
        transport: String,
    ): Boolean =
        when (mode) {
            "lan_only" -> transport == "lan" || transport == "wifi" || transport == "ethernet"
            "ble_only" -> transport == "ble"
            else -> true
        }

    private fun primaryRank(
        primary: String?,
        transport: String,
    ): Int {
        if (primary == null) return 1
        if (primary == transport) return 0
        if (primary == "lan" && transport in setOf("wifi", "ethernet")) return 0
        return 1
    }

    private fun healthRank(state: String): Int = if (state == "connected") 0 else 1

    private fun stableRank(transport: String): Int =
        when (transport) {
            "lan", "ethernet", "wifi" -> 0
            else -> 1
        }

    private fun score(path: TransportPathStatus): Long {
        val latency = (path.rttMs ?: 500).coerceAtMost(5_000)
        val loss = ((path.lossPercent ?: 0.0) * 10).toLong().coerceAtMost(1_000)
        val throughput = (path.throughputKbps ?: 0).coerceAtMost(100_000)
        return throughput - latency * 20 - loss * 50 + if (path.state == "connected") 10_000 else 0
    }

    private fun measuredScore(
        path: TransportPathStatus,
        preference: PathPreference,
    ): Double {
        val latency = ((path.p95RttMs ?: path.rttMs ?: 500).coerceAtMost(5_000) / 5_000.0)
        val loss = ((path.lossPercent ?: 100.0) / 100.0 + ((path.reconnects ?: 0) / 20.0) * 0.25).coerceIn(0.0, 1.0)
        val energy = ((path.energyPercentPerHour ?: 1.0) / 5.0).coerceIn(0.0, 1.0)
        return 1.0 - preference.latencyWeight * latency - preference.lossWeight * loss - preference.energyWeight * energy
    }
}
