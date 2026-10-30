package app.cadenza.remote

import kotlinx.coroutines.flow.update

fun RemoteModel.pairBluetooth(
    pin: String,
    name: String,
) {
    try {
        require(pin.length == 4 && pin.all { it in '0'..'9' }) { "Enter the four-digit PIN shown by Cadenza Host." }
        require(name.trim().length in 1..80) { "Enter the name that should appear beside your requests." }
        require(name.none { it.isISOControl() }) { "Use a name without control characters." }
        invitation = null
        pairingPin = pin
        endpoints.clear()
        remoteName = name.trim()
        transportMode = "ble"
        preferences.write("transport_mode" to transportMode)
        mutable.update { it.copy(transportMode = transportMode) }
        connect()
    } catch (error: Exception) {
        showError("Could not pair over Bluetooth", error.message ?: "Enter the current Host PIN and retry.")
    }
}
