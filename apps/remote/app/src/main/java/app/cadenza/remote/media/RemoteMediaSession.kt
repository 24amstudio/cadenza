package app.cadenza.remote.media

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.graphics.scale
import app.cadenza.remote.MainActivity

data class MediaSessionState(
    val active: Boolean,
    val playing: Boolean,
    val title: String,
    val artist: String,
    val album: String,
    val artworkUrl: String?,
    val artworkBytes: ByteArray?,
    val occurrenceId: String,
    val positionMs: Long,
    val durationMs: Long?,
    val canInterrupt: Boolean,
)

/**
 * The system media session. Metadata and playback state are published only when they change, so the system scrubber
 * interpolates between updates instead of this app timing every frame.
 */
class RemoteMediaSession(
    context: Context,
    private val onAction: (String) -> Unit,
) {
    private val session = MediaSession(context, "Cadenza Remote")

    val token: MediaSession.Token
        get() = session.sessionToken

    init {
        session.setSessionActivity(
            PendingIntent.getActivity(
                context,
                43130,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            ),
        )
        session.setCallback(
            object : MediaSession.Callback() {
                override fun onPlay() = onAction("play")

                override fun onPause() = onAction("pause")

                override fun onSkipToNext() = onAction("next")

                override fun onSkipToPrevious() = onAction("previous")

                override fun onSeekTo(pos: Long) = onAction("seek:" + pos.coerceAtLeast(0))
            },
            Handler(Looper.getMainLooper()),
        )
    }

    fun update(state: MediaSessionState) {
        if (!state.active) {
            session.isActive = false
            session.setPlaybackState(
                PlaybackState
                    .Builder()
                    .setState(PlaybackState.STATE_NONE, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 0f)
                    .build(),
            )
            session.setMetadata(null)
            return
        }
        session.setMetadata(metadata(state))
        val timing = transportTiming(state.playing, state.positionMs, SystemClock.elapsedRealtime())
        session.setPlaybackState(
            PlaybackState
                .Builder()
                .setActions(actions(state))
                .setState(timing.state, timing.positionMs, timing.speed, timing.updatedAtMs)
                .build(),
        )
        session.isActive = true
    }

    private fun metadata(state: MediaSessionState): MediaMetadata {
        val builder =
            MediaMetadata
                .Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, state.title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, state.artist)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, state.album)
                .putString(MediaMetadata.METADATA_KEY_MEDIA_ID, state.occurrenceId)
        state.artworkUrl?.let { builder.putString(MediaMetadata.METADATA_KEY_ART_URI, it) }
        albumArt(state.artworkBytes)?.let { builder.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, it) }
        state.durationMs?.let { builder.putLong(MediaMetadata.METADATA_KEY_DURATION, it) }
        return builder.build()
    }

    // SystemUI reads album art for its tonal accent. A square 256-pixel copy keeps that read cheap.
    private fun albumArt(bytes: ByteArray?): Bitmap? {
        val decoded = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } ?: return null
        return decoded.scale(ALBUM_ART_PX, ALBUM_ART_PX)
    }

    private fun actions(state: MediaSessionState): Long =
        PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_SEEK_TO or
            if (state.canInterrupt) {
                PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS
            } else {
                0L
            }

    fun release() {
        session.isActive = false
        session.release()
    }

    private companion object {
        const val ALBUM_ART_PX = 256
    }
}
