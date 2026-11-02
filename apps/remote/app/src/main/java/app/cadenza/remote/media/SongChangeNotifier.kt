package app.cadenza.remote.media

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import app.cadenza.remote.MainActivity
import app.cadenza.remote.R
import app.cadenza.remote.data.Song

/** True when a connected Remote sees a different occurrence than the one it had, so a new song has started. */
internal fun isSongChange(
    connected: Boolean,
    previous: String?,
    current: String?,
): Boolean = connected && previous != null && current != null && current != previous

/**
 * Posts one card for the song Host is playing. Every change replaces the card, so a busy queue never stacks cards.
 */
class SongChangeNotifier(
    private val context: Context,
) {
    private val manager = context.getSystemService(NotificationManager::class.java)

    fun show(
        song: Song,
        host: String,
        artworkBytes: ByteArray?,
    ) {
        if (!canPostNotifications(context, manager)) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Song changes", NotificationManager.IMPORTANCE_DEFAULT).apply {
                setSound(null, null)
                enableVibration(false)
            },
        )
        val open =
            PendingIntent.getActivity(
                context,
                ID,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        val notification =
            Notification
                .Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(song.title)
                .setContentText(listOf(song.artist, host).filter { it.isNotBlank() }.joinToString(" · "))
                .setContentIntent(open)
                .setAutoCancel(true)
                .setTimeoutAfter(TIMEOUT_MS)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setLocalOnly(true)
                .apply {
                    artworkBytes
                        ?.let { bytes -> BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }
                        ?.let(::setLargeIcon)
                }.build()
        manager.notify(ID, notification)
    }

    companion object {
        const val ID = 43131
        private const val CHANNEL = "song-changes"
        private const val TIMEOUT_MS = 15_000L
    }
}
