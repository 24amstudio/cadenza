package app.cadenza.remote.network

import app.cadenza.remote.data.TransportPathStatus
import kotlin.math.abs

data class PathMeasurement(
    val transport: String,
    val rttMs: Long,
    val lossPercent: Double,
    val energyPercentPerHour: Double?,
    val confidence: String,
    val sampleAgeMs: Long,
)

class PathMeasurementService {
    private val samples = mutableMapOf<String, MutableList<PathMeasurement>>()

    fun record(sample: PathMeasurement) {
        val path = samples.getOrPut(sample.transport) { mutableListOf() }
        path += sample
        if (path.size > 32) path.removeAt(0)
    }

    fun statuses(nowMs: Long): List<TransportPathStatus> =
        samples.map { (transport, values) ->
            val recent = values.takeLast(8)
            val latest = recent.last()
            TransportPathStatus(
                transport = transport,
                state = "connected",
                rssiDbm = null,
                rttMs = recent.map { it.rttMs }.sorted()[recent.size / 2],
                p95RttMs = recent.map { it.rttMs }.sorted()[(recent.size * 95 / 100).coerceAtMost(recent.lastIndex)],
                lossPercent = recent.map { it.lossPercent }.average(),
                throughputKbps = null,
                backlogBytes = 0,
                energyPercentPerHour = recent.mapNotNull { it.energyPercentPerHour }.average().takeIf { !it.isNaN() },
                energyConfidence = recent.maxBy { confidenceRank(it.confidence) }.confidence,
                sampleAgeMs = (nowMs - latest.sampleAgeMs).coerceAtLeast(0),
            )
        }

    private fun confidenceRank(value: String): Int =
        when (value) {
            "high" -> 3
            "medium" -> 2
            else -> 1
        }
}

data class PathPreference(
    val latencyWeight: Double,
    val lossWeight: Double,
    val energyWeight: Double,
) {
    init {
        require(abs(latencyWeight + lossWeight + energyWeight - 1.0) < 0.001)
    }

    companion object {
        val responsiveness = PathPreference(0.70, 0.20, 0.10)
        val balanced = PathPreference(0.40, 0.25, 0.35)
        val battery = PathPreference(0.15, 0.25, 0.60)
    }
}
