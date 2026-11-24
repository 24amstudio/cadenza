package app.cadenza.remote.media

import android.media.session.PlaybackState

/**
 * The position, speed and time stamp published to the system media session. The system interpolates the scrubber from
 * these values, so they change only when playback state, track or seek position changes, never on a timer.
 */
internal data class TransportTiming(
    val state: Int,
    val positionMs: Long,
    val speed: Float,
    val updatedAtMs: Long,
)

internal fun transportTiming(
    playing: Boolean,
    positionMs: Long,
    nowElapsedMs: Long,
): TransportTiming =
    TransportTiming(
        state = if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
        positionMs = positionMs.coerceAtLeast(0),
        speed = if (playing) 1f else 0f,
        updatedAtMs = nowElapsedMs,
    )
