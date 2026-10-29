package app.cadenza.remote.data

data class TransportPolicy(
    val mode: String,
    val selection: String,
    val primary: String?,
    val bulk: String?,
    val manual: String? = null,
    val minimumDwellMs: Long = 30_000,
) {
    init {
        require(mode in setOf("lan_only", "ble_only", "hybrid")) { "Invalid transport mode." }
        require(selection in setOf("deterministic", "opportunistic")) { "Invalid transport selection." }
        require(primary == null || primary in setOf("lan", "wifi", "ethernet", "ble")) { "Invalid primary transport." }
        require(bulk == null || bulk in setOf("lan", "ble", "auto")) { "Invalid bulk transport." }
    }
}

data class TransportPathStatus(
    val transport: String,
    val state: String,
    val rssiDbm: Int?,
    val rttMs: Long?,
    val lossPercent: Double?,
    val throughputKbps: Long?,
    val backlogBytes: Long?,
    val energyPercentPerHour: Double? = null,
    val energyConfidence: String? = null,
    val sampleAgeMs: Long? = null,
    val p95RttMs: Long? = null,
    val reconnects: Long? = null,
    val activeRemotes: Long? = null,
) {
    init {
        require(transport in setOf("lan", "wifi", "ethernet", "ble")) { "Invalid transport path." }
        require(state in setOf("connected", "connecting", "degraded", "disconnected")) { "Invalid transport state." }
        require(rssiDbm == null || rssiDbm in -127..0) { "Invalid RSSI." }
        require(lossPercent == null || lossPercent in 0.0..100.0) { "Invalid packet loss." }
        require(energyPercentPerHour == null || energyPercentPerHour >= 0.0) { "Invalid energy estimate." }
        require(energyConfidence == null || energyConfidence in setOf("low", "medium", "high")) { "Invalid energy confidence." }
    }
}

data class DevicePowerStatus(
    val batteryPercent: Int?,
    val charging: Boolean?,
    val source: String?,
)

data class DeviceResourceStatus(
    val cpuPercent: Double?,
    val memoryBytes: Long?,
    val storageBytes: Long?,
)

data class TransportConstraints(
    val maximumLatencyMs: Long = 500,
    val maximumLossPercent: Double = 15.0,
    val requireReliable: Boolean = false,
    val minimumReliabilityPercent: Double = 85.0,
)

data class SessionStatus(
    val reportedAtMs: Long,
    val device: String,
    val power: DevicePowerStatus?,
    val resources: DeviceResourceStatus?,
    val paths: List<TransportPathStatus>,
    val constraints: TransportConstraints? = null,
) {
    init {
        require(device == "host" || device == "remote") { "Invalid status device." }
        require(paths.size <= 4) { "Too many transport paths." }
    }
}

data class EffectiveTransportDecision(
    val selected: String?,
    val bulk: String?,
    val reason: String,
    val hostPreference: String,
    val remotePreference: String?,
    val policyMode: String = "balanced_negotiation",
    val confidence: String = "low",
)
