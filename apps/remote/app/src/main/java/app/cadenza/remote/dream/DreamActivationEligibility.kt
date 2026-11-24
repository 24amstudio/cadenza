package app.cadenza.remote.dream

/** The conditions that keep the screen saver on. */
data class DreamConditions(
    val hostConnected: Boolean,
    val hostPlaying: Boolean,
    val hasCurrentSong: Boolean,
    val charging: Boolean,
)

/**
 * Decides whether the screen saver may stay up. Charging and a live Host connection are required at every moment. A pause
 * with a song loaded ends the screen saver at once. Only the gap between two songs, when the Host has no current song, is
 * tolerated for [graceMs], so consecutive tracks do not end it. A screen saver that starts while the Host is not playing
 * never gets that grace.
 */
class DreamActivationEligibility(
    private val graceMs: Long = TRANSITION_GRACE_MS,
) {
    private var lastPlayingAtMs: Long? = null

    fun canActivate(
        conditions: DreamConditions,
        nowMs: Long,
    ): Boolean {
        if (!conditions.charging || !conditions.hostConnected) {
            lastPlayingAtMs = null
            return false
        }
        if (conditions.hostPlaying) {
            lastPlayingAtMs = nowMs
            return true
        }
        if (conditions.hasCurrentSong) return false
        val since = lastPlayingAtMs ?: return false
        return nowMs - since <= graceMs
    }

    companion object {
        const val TRANSITION_GRACE_MS = 5_000L
    }
}
