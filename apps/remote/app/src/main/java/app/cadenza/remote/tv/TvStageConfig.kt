package app.cadenza.remote.tv

import java.net.URI

/** Where the stage connects, and whether this device should run the stage at all. Pure, so it can be tested. */
internal object TvStageConfig {
    const val ROLE = "android_tv_receiver"
    private const val SOCKET_PATH = "/cast/live"

    /**
     * The socket URL for a Host address the person typed, such as `192.168.1.10:8765` or `http://192.168.1.10:8765`.
     * The stage is plain HTTP on the LAN, so anything else, including HTTPS, is refused.
     */
    fun socketUrl(address: String): String? {
        val trimmed = address.trim().trimEnd('/')
        val withScheme = if (trimmed.contains("://")) trimmed else "http://$trimmed"
        val uri = runCatching { URI(withScheme) }.getOrNull() ?: return null
        if (uri.scheme != "http" || uri.host.isNullOrBlank()) return null
        if (!uri.rawPath.isNullOrEmpty() || uri.rawQuery != null) return null
        val port = if (uri.port == -1) "" else ":${uri.port}"
        return "ws://${uri.host}$port$SOCKET_PATH?role=$ROLE"
    }

    /**
     * Whether this device starts the stage on launch. A TV always does, unless the person turned the stage off in
     * Settings. A tablet or phone runs it only when the person turned it on.
     */
    fun startsStage(
        isTelevision: Boolean,
        manualSetting: Boolean?,
    ): Boolean = manualSetting ?: isTelevision
}
