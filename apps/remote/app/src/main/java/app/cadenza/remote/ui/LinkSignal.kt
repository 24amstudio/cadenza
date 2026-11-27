package app.cadenza.remote.ui

/** Signal bars for the link to Cadenza Host, out of four. Same thresholds as the web Remote's sidebar. */
internal const val SIGNAL_BAR_COUNT = 4

/** The radio that carries the control link. */
internal enum class LinkTransport { BLUETOOTH, WIFI }

/**
 * Bars follow the Remote's own clock round trip to the Host, which is what a control waits for. A live link with no
 * round trip yet shows one bar, and a dropped link shows none.
 */
internal fun linkSignalBars(
    connected: Boolean,
    roundTripMs: Long?,
): Int {
    if (!connected) return 0
    val roundTrip = roundTripMs ?: return 1
    return when {
        roundTrip <= 80 -> 4
        roundTrip <= 200 -> 3
        roundTrip <= 500 -> 2
        else -> 1
    }
}

/**
 * The transport of the live link. A fixed mode names its own transport. Hybrid mode follows the Host's decision, and
 * is null until the Host has made one.
 */
internal fun linkTransportOf(
    transportMode: String,
    selected: String?,
): LinkTransport? =
    when (transportMode) {
        "ble" -> LinkTransport.BLUETOOTH
        "lan" -> LinkTransport.WIFI
        else ->
            when (selected) {
                "ble" -> LinkTransport.BLUETOOTH
                "lan", "wifi", "ethernet" -> LinkTransport.WIFI
                else -> null
            }
    }
