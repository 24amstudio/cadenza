package app.cadenza.remote.energy

import androidx.compose.runtime.Immutable

/**
 * The concrete work limits for a tier. Each knob has one consumer:
 * - [lyricFrameCapFps]: per-word sweep frame loop (`rememberSweeps`).
 * - [lyricBlur]: receding lines get a blur effect; off recedes them by opacity alone.
 * - [reduceTransitions]: lyric tier fades, follow glide and surface/song swaps become instant.
 * - [motionArtwork]: animated cover video is requested and played.
 * - [artworkMaxEdgePx]: longest edge a full-size cover is decoded to.
 * - [lyricTickMs] / [progressTickMs]: position sampling of the lyrics screen and of the timeline-only screens.
 * - [clockPingMs] / [statusIntervalMs]: clock samples while playing and the idle `session.status` republish.
 * - [efficientTransport]: report the "remote_efficiency" preference when the user left the default.
 */
@Immutable
data class EnergyProfile(
    val tier: EnergyTier,
    val lyricFrameCapFps: Int,
    val lyricBlur: Boolean,
    val reduceTransitions: Boolean,
    val motionArtwork: Boolean,
    val artworkMaxEdgePx: Int,
    val lyricTickMs: Long,
    val progressTickMs: Long,
    val clockPingMs: Long,
    val statusIntervalMs: Long,
    val efficientTransport: Boolean,
) {
    /** The transport preference to report: an explicit user choice always wins over the saver default. */
    fun reportedPreference(userPreference: String): String =
        if (efficientTransport && userPreference == "balanced") "remote_efficiency" else userPreference

    companion object {
        val Full = of(EnergyTier.FULL, EnergySettings())

        fun of(
            tier: EnergyTier,
            settings: EnergySettings,
        ): EnergyProfile =
            when (tier) {
                EnergyTier.FULL ->
                    EnergyProfile(tier, 60, true, false, true, 1_024, 100, 250, 5_000, 15_000, false)
                EnergyTier.BALANCED ->
                    EnergyProfile(tier, 30, true, false, true, 768, 150, 500, 10_000, 20_000, false)
                EnergyTier.SAVER ->
                    EnergyProfile(
                        tier = tier,
                        lyricFrameCapFps = 20,
                        lyricBlur = settings.lyricBlurInSaver,
                        reduceTransitions = true,
                        motionArtwork = settings.motionArtworkInSaver,
                        artworkMaxEdgePx = 512,
                        lyricTickMs = 250,
                        progressTickMs = 1_000,
                        clockPingMs = 15_000,
                        statusIntervalMs = 30_000,
                        efficientTransport = true,
                    )
            }
    }
}
