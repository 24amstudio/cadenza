package app.cadenza.remote.data

data class TransportMethodOption(
    val id: String,
    val label: String,
    val description: String,
    val requiresNearbyPermission: Boolean = false,
)

object TransportMethodRegistry {
    val available: List<TransportMethodOption> =
        listOf(
            TransportMethodOption("lan", "Wi-Fi / LAN", "Fast local network session."),
            TransportMethodOption("ble", "Bluetooth", "Nearby low-power session.", requiresNearbyPermission = true),
        )

    fun selectedFor(mode: String): Set<String> =
        when (mode) {
            "ble" -> setOf("ble")
            "hybrid" -> setOf("lan", "ble")
            else -> setOf("lan")
        }

    fun modeFor(selected: Set<String>): String? =
        when {
            selected == setOf("lan") -> "lan"
            selected == setOf("ble") -> "ble"
            selected == setOf("lan", "ble") -> "hybrid"
            else -> null
        }
}
