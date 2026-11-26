package app.cadenza.remote.model

import org.json.JSONObject

/** The stored preference that lets the hardware volume buttons move Music's volume on Host. It stays off until turned on. */
internal const val VOLUME_ROCKER_CONTROL = "volume_rocker_control"

internal object VolumeRocker {
    const val STEP_PERCENT = 5

    fun target(
        current: Int,
        up: Boolean,
    ): Int = (current + if (up) STEP_PERCENT else -STEP_PERCENT).coerceIn(0, 100)
}

/**
 * Sends one volume step to Host when the rocker control is on and Host is connected. Returns whether the key press was
 * used, so the system keeps the buttons otherwise.
 */
internal fun RemoteModel.adjustVolumeFromRocker(up: Boolean): Boolean {
    val current = state.value
    val volume = current.snapshot?.volume ?: return false
    if (!current.volumeRockerControl || !current.connected) return false
    command(
        JSONObject().put("kind", "playback.volume").put("percent", VolumeRocker.target(volume, up)),
        "playback.volume",
    )
    return true
}
