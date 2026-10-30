package app.cadenza.remote.network

import app.cadenza.remote.data.PairingInvitation
import app.cadenza.remote.data.Wire

internal fun parsePairingInvitation(
    payload: ByteArray,
    name: String,
): PairingInvitation {
    val invitation =
        if (Wire.isCompactInvitation(payload)) {
            Wire.invitation(payload)
        } else {
            Wire.invitation(String(payload, Charsets.UTF_8))
        }
    require(name.trim().length in 1..80) { "Enter the name that should appear beside your requests." }
    require(name.none { it.isISOControl() }) { "Use a name without control characters." }
    return invitation
}
