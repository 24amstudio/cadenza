package app.cadenza.remote

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

data class SessionStatus(
    val active: Boolean,
    val connected: Boolean,
    val host: String,
    val title: String,
    val artist: String,
    val playing: Boolean,
    val monitoring: Boolean,
) {
    companion object {
        fun from(state: RemoteState): SessionStatus =
            SessionStatus(
                state.sessionActive,
                state.connected,
                state.profile?.name.orEmpty(),
                state.snapshot
                    ?.current
                    ?.song
                    ?.title
                    .orEmpty(),
                state.snapshot
                    ?.current
                    ?.song
                    ?.artist
                    .orEmpty(),
                state.snapshot?.playing == true,
                state.monitoringSong,
            )
    }
}

class SessionNotification(
    private val context: Context,
) {
    private val manager = context.getSystemService(NotificationManager::class.java)

    fun update(status: SessionStatus) {
        if (!status.active || !manager.areNotificationsEnabled() ||
            (
                Build.VERSION.SDK_INT >= 33 &&
                    ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            )
        ) {
            clear()
            return
        }
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Control session", NotificationManager.IMPORTANCE_LOW))
        val open =
            PendingIntent.getActivity(
                context,
                43129,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        val text =
            when {
                !status.connected -> "Reconnecting to " + status.host
                status.title.isEmpty() -> "Connected to " + status.host
                else -> (if (status.playing) "Playing" else "Paused") + " on " + status.host + " · " + status.artist
            }
        val builder =
            NotificationCompat
                .Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(status.title.ifEmpty { "Cadenza Remote" })
                .setContentText(text)
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
        // An explicitly pinned, currently playing song is monitoring; a generic connection is not a Live Update.
        if (Build.VERSION.SDK_INT >= 36 && status.monitoring && status.connected && status.playing &&
            manager.canPostPromotedNotifications()
        ) {
            builder.setRequestPromotedOngoing(true)
            builder.setShortCriticalText("Music")
            val unpin =
                PendingIntent.getBroadcast(
                    context,
                    43129,
                    Intent(context, SessionUnpinReceiver::class.java),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            builder.addAction(0, "Unpin", unpin)
        }
        val notification: Notification = builder.build()
        manager.notify(ID, notification)
    }

    fun clear() = manager.cancel(ID)

    companion object {
        const val ID = 43129
        private const val CHANNEL = "control-session"
    }
}
