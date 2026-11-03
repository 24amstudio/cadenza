package app.cadenza.remote.model

import app.cadenza.remote.data.HostProfile
import app.cadenza.remote.data.PairingInvitation
import app.cadenza.remote.data.nullableString
import app.cadenza.remote.network.LocalEndpoint
import org.json.JSONObject

internal fun hostProfileFromWelcome(
    value: JSONObject,
    endpoint: LocalEndpoint?,
    invite: PairingInvitation?,
    previous: HostProfile?,
): HostProfile {
    val address =
        value.nullableString("host_address") ?: endpoint?.address ?: invite?.host ?: previous?.address
            ?: error("Host did not provide a reachable address.")
    val port =
        value.optInt("host_port", 0).takeIf { it in 1..65_535 } ?: endpoint?.port ?: invite?.port
            ?: previous?.port ?: error("Host did not provide a reachable port.")
    return HostProfile(
        value.getString("host_id"),
        value.getString("host_name"),
        address,
        port,
        value.getString("remote_id"),
    )
}

internal fun RemoteModel.connectionFallback(
    invite: PairingInvitation?,
    profile: HostProfile?,
): LocalEndpoint? =
    if (transportMode == "ble" && pairingPin != null) {
        null
    } else {
        LocalEndpoint(
            invite?.host ?: profile?.address ?: error("The Host endpoint is unavailable."),
            invite?.port ?: profile?.port ?: error("The Host port is unavailable."),
        )
    }
