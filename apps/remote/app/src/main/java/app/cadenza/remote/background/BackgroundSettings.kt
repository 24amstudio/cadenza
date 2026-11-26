package app.cadenza.remote.background

import app.cadenza.remote.data.StoredSettings

/** Background behavior the user controls. */
data class BackgroundSettings(
    val lockScreenMotionArtwork: Boolean = true,
    val silentPlaybackKeepAlive: Boolean = true,
)

/** HarmonyOS and EMUI put idle background apps to sleep aggressively, so the keep-alive starts on there. */
fun silentKeepAliveDefault(manufacturer: String): Boolean = manufacturer.trim().lowercase() in HUAWEI_MANUFACTURERS

private val HUAWEI_MANUFACTURERS = setOf("huawei", "honor")

/** Additive rows, so an older install reads the defaults for anything it never saved. */
object BackgroundSettingsStore {
    private const val LOCK_SCREEN_MOTION = "lock_screen_motion"
    private const val SILENT_KEEP_ALIVE = "silent_keep_alive"

    fun load(
        store: StoredSettings,
        manufacturer: String,
    ): BackgroundSettings =
        BackgroundSettings(
            lockScreenMotionArtwork = store.getString(LOCK_SCREEN_MOTION)?.toBooleanStrictOrNull() ?: true,
            silentPlaybackKeepAlive =
                store.getString(SILENT_KEEP_ALIVE)?.toBooleanStrictOrNull() ?: silentKeepAliveDefault(manufacturer),
        )

    fun save(
        store: StoredSettings,
        settings: BackgroundSettings,
    ) = store.write(
        LOCK_SCREEN_MOTION to settings.lockScreenMotionArtwork.toString(),
        SILENT_KEEP_ALIVE to settings.silentPlaybackKeepAlive.toString(),
    )
}
