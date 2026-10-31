package app.cadenza.remote.model

import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.nullableString
import kotlinx.coroutines.flow.update
import org.json.JSONObject

data class HostUpdateStatus(
    val state: String,
    val version: String?,
    val message: String?,
)

internal fun RemoteModel.checkHostUpdate() = sendHostUpdate("check", "checking")

internal fun RemoteModel.installHostUpdate() = sendHostUpdate("install", "requesting")

private fun RemoteModel.sendHostUpdate(
    action: String,
    pendingState: String,
) {
    if (!mutable.value.connected || "host.update" !in mutable.value.capabilities) return
    mutable.update { it.copy(hostUpdate = HostUpdateStatus(pendingState, null, null)) }
    connection?.send(Wire.frame("host.update").put("update_action", action).put("request_id", id()))
}

internal fun RemoteModel.applyHostUpdateStatus(frame: JSONObject) {
    val status =
        HostUpdateStatus(
            frame.optString("update_state"),
            frame.nullableString("update_version"),
            frame.nullableString("message"),
        )
    mutable.update { it.copy(hostUpdate = status) }
}

internal fun hostUpdateMessage(status: HostUpdateStatus?): String? {
    val update = status ?: return null
    return when (update.state) {
        "checking" -> "Checking for a Cadenza Host update."
        "requesting" -> "Asking Cadenza Host to install the update."
        "current" -> update.message ?: "Cadenza Host is up to date."
        "ready" -> "Cadenza Host ${update.version} is ready to install."
        "installing" -> "Cadenza Host is restarting to install ${update.version}. This Remote reconnects automatically."
        "failed", "unavailable" -> update.message ?: "Cadenza Host could not update."
        else -> null
    }
}
