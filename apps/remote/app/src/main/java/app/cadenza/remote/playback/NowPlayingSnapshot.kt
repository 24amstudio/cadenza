package app.cadenza.remote.playback

import app.cadenza.remote.data.LyricDocument
import app.cadenza.remote.model.RemoteState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File

/**
 * What the home widget, screen saver and lock screen show. The Remote model publishes it whenever the playback state
 * changes, so each surface reads one shared, already-validated copy rather than its own connection. The connection and
 * playback flags stay present between songs, so a surface can tell a short gap from a lost Host.
 */
data class NowPlayingSnapshot(
    val connected: Boolean,
    val playing: Boolean,
    val hasCurrentSong: Boolean,
    val occurrenceId: String,
    val title: String,
    val artist: String,
    val artwork: ByteArray?,
    val motion: File?,
    val lyrics: LyricDocument?,
    val positionMs: Long,
    val sampledAtElapsedMs: Long,
    val motionEnabled: Boolean,
) {
    /** The position at [elapsedMs], moved forward from the last sample only while the Host is playing. */
    fun positionAt(elapsedMs: Long): Long = if (playing) positionMs + (elapsedMs - sampledAtElapsedMs).coerceAtLeast(0) else positionMs

    companion object {
        fun from(
            state: RemoteState,
            motionEnabled: Boolean,
        ): NowPlayingSnapshot {
            val current = state.snapshot?.current
            return NowPlayingSnapshot(
                connected = state.connected,
                playing = state.snapshot?.playing == true,
                hasCurrentSong = current != null,
                occurrenceId = current?.occurrenceId.orEmpty(),
                title = current?.song?.title.orEmpty(),
                artist = current?.song?.artist.orEmpty(),
                artwork = current?.song?.artworkUrl?.let { state.artwork[it] },
                motion = current?.let { state.motion?.takeIf { motion -> motion.occurrenceId == it.occurrenceId }?.file },
                lyrics = current?.let { state.lyrics?.takeIf { lyrics -> lyrics.occurrenceId == it.occurrenceId } },
                positionMs = current?.positionMs ?: 0,
                sampledAtElapsedMs = state.lastStateAt,
                motionEnabled = motionEnabled,
            )
        }
    }
}

/** Process-wide holder for the latest snapshot. A null value means no Host state has arrived yet. */
object NowPlayingHub {
    private val current = MutableStateFlow<NowPlayingSnapshot?>(null)
    val snapshot: StateFlow<NowPlayingSnapshot?> = current.asStateFlow()

    fun publish(value: NowPlayingSnapshot?) {
        current.value = value
    }
}
