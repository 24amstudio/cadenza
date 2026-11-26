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
    fun socketUrl(address: String): String? = hostAuthority(address)?.let { "ws://$it$SOCKET_PATH?role=$ROLE" }

    /**
     * The page a phone opens to approve this TV. The TV's QR code carries it, so one scan opens this Host's web Remote
     * with the PIN filled in. Null when the address or PIN cannot form a link.
     */
    fun approvalUrl(
        address: String,
        pin: String,
    ): String? {
        if (pin.length != PIN_LENGTH || !pin.all { it.isDigit() }) return null
        return hostAuthority(address)?.let { "http://$it/?stage=$pin" }
    }

    const val PIN_LENGTH = 4

    /** The `host:port` of a plain-HTTP address the person typed. Null for HTTPS, paths, queries, or blank input. */
    private fun hostAuthority(address: String): String? {
        val trimmed = address.trim().trimEnd('/')
        val withScheme = if (trimmed.contains("://")) trimmed else "http://$trimmed"
        val uri = runCatching { URI(withScheme) }.getOrNull() ?: return null
        if (uri.scheme != "http" || uri.host.isNullOrBlank()) return null
        if (!uri.rawPath.isNullOrEmpty() || uri.rawQuery != null) return null
        val port = if (uri.port == -1) "" else ":${uri.port}"
        return "${uri.host}$port"
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
