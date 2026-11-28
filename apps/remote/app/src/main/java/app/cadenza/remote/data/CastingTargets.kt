package app.cadenza.remote.data

fun castingTargets(
    cast: CastState?,
    remoteAudioTarget: String?,
): List<String> =
    buildList {
        remoteAudioTarget?.let { add(it) }
        if (cast != null) {
            cast.transmit?.takeIf { it.state == "transmitting" }?.let { add(castDeviceLabel(cast, it.device)) }
            cast.stages.filter { it.transmitting }.forEach { add(it.name) }
        }
    }

private fun castDeviceLabel(
    cast: CastState,
    device: String?,
): String {
    val name = device ?: return "Google Cast"

    return cast.devices.firstOrNull { it.name == name }?.label ?: name
}
