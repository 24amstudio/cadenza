package app.cadenza.remote.media

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import app.cadenza.remote.MainActivity

data class MediaSessionState(
    val active: Boolean,
    val playing: Boolean,
    val title: String,
    val artist: String,
    val album: String,
    val artworkUrl: String?,
    val occurrenceId: String,
    val positionMs: Long,
    val durationMs: Long?,
    val canInterrupt: Boolean,
)

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
        val metadata =
            MediaMetadata
                .Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, state.title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, state.artist)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, state.album)
                .putString(MediaMetadata.METADATA_KEY_MEDIA_ID, state.occurrenceId)
                .apply { state.artworkUrl?.let { putString(MediaMetadata.METADATA_KEY_ART_URI, it) } }
                .apply { state.durationMs?.let { putLong(MediaMetadata.METADATA_KEY_DURATION, it) } }
                .build()
        val actions =
            PlaybackState.ACTION_PLAY or
                PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_PLAY_PAUSE or
                PlaybackState.ACTION_SEEK_TO or
                if (state.canInterrupt) PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS else 0L
        session.setMetadata(metadata)
        session.setPlaybackState(
            PlaybackState
                .Builder()
                .setActions(actions)
                .setState(
                    if (state.playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    state.positionMs.coerceAtLeast(0),
                    if (state.playing) 1f else 0f,
                    SystemClock.elapsedRealtime(),
                ).build(),
        )
        session.isActive = true
    }

    fun release() {
        session.isActive = false
        session.release()
    }
}
