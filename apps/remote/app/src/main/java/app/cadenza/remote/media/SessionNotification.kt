package app.cadenza.remote.media

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.media.session.MediaSession
import android.os.Build
import androidx.core.content.ContextCompat
import app.cadenza.remote.MainActivity
import app.cadenza.remote.R
import app.cadenza.remote.model.RemoteState

data class SessionStatus(
    val active: Boolean,
    val connected: Boolean,
    val host: String,
    val title: String,
    val artist: String,
    val playing: Boolean,
    val pinned: Boolean,
    val occurrenceId: String = "",
    val canInterrupt: Boolean = false,
) {
    companion object {
        fun from(state: RemoteState): SessionStatus {
            val current = state.snapshot?.current
            val playing = state.snapshot?.playing == true
            return SessionStatus(
                state.sessionActive || (state.connected && playing && current != null),
                state.connected,
                state.profile?.name.orEmpty(),
                current?.song?.title.orEmpty(),
                current?.song?.artist.orEmpty(),
                playing,
                state.connected && playing && current != null,
                current?.occurrenceId.orEmpty(),
                current?.requestedBy?.let { requester ->
                    requester == state.profile?.remoteId || state.snapshot.allowCrossRemoteEdits
                } ?: true,
            )
        }
    }
}

class SessionNotification(
    private val context: Context,
) {
    private val manager = context.getSystemService(NotificationManager::class.java)

    fun update(
        status: SessionStatus,
        mediaToken: MediaSession.Token? = null,
    ) {
        if (!status.active || !manager.areNotificationsEnabled() ||
            (
                Build.VERSION.SDK_INT >= 33 &&
                    ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                    android.content.pm.PackageManager.PERMISSION_GRANTED
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
                else -> (if (status.playing) "Playing" else "Paused") + " on " + status.host + " | " + status.artist
            }
        val builder =
            Notification
                .Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(status.title.ifEmpty { "Cadenza Remote" })
                .setContentText(text)
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setCategory(Notification.CATEGORY_STATUS)
                .setLocalOnly(true)
        if (mediaToken != null && status.title.isNotEmpty()) {
            val style = Notification.MediaStyle().setMediaSession(mediaToken)
            if (status.canInterrupt) {
                style.setShowActionsInCompactView(0, 1, 2)
                builder.addAction(Notification.Action.Builder(actionIcon("previous"), "Previous", action("previous")).build())
                builder.addAction(
                    Notification.Action
                        .Builder(
                            actionIcon(if (status.playing) "pause" else "play"),
                            if (status.playing) "Pause" else "Play",
                            action(if (status.playing) "pause" else "play"),
                        ).build(),
                )
                builder.addAction(Notification.Action.Builder(actionIcon("next"), "Next", action("next")).build())
            } else {
                style.setShowActionsInCompactView(0)
                builder.addAction(
                    Notification.Action
                        .Builder(
                            actionIcon(if (status.playing) "pause" else "play"),
                            if (status.playing) "Pause" else "Play",
                            action(if (status.playing) "pause" else "play"),
                        ).build(),
                )
            }
            builder.setStyle(style)
        }
        manager.notify(ID, builder.build())
        if (Build.VERSION.SDK_INT >= 36 && status.pinned && status.connected && status.playing &&
            manager.canPostPromotedNotifications()
        ) {
            val live =
                Notification
                    .Builder(context, CHANNEL)
                    .setSmallIcon(R.drawable.ic_notification)
                    .setContentTitle(status.title)
                    .setContentText(text)
                    .setStyle(Notification.BigTextStyle().bigText(text))
                    .setContentIntent(open)
                    .setOngoing(true)
                    .setOnlyAlertOnce(true)
                    .setVisibility(Notification.VISIBILITY_PRIVATE)
                    .setCategory(Notification.CATEGORY_STATUS)
                    .setLocalOnly(true)
                    .setRequestPromotedOngoing(true)
                    .setShortCriticalText("Music")
                    .build()
            manager.notify(LIVE_ID, live)
        } else {
            manager.cancel(LIVE_ID)
        }
    }

    private fun action(value: String): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            value.hashCode(),
            Intent(context, MediaActionReceiver::class.java)
                .setAction(MediaActionReceiver.ACTION)
                .putExtra(MediaActionReceiver.ACTION, value),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun actionIcon(action: String): Icon {
        val resource =
            when (action) {
                "previous" -> android.R.drawable.ic_media_previous
                "next" -> android.R.drawable.ic_media_next
                "pause" -> android.R.drawable.ic_media_pause
                "play" -> android.R.drawable.ic_media_play
                else -> android.R.drawable.ic_delete
            }
        return Icon.createWithResource(context, resource)
    }

    fun clear() {
        manager.cancel(ID)
        manager.cancel(LIVE_ID)
    }

    companion object {
        const val ID = 43129
        const val LIVE_ID = 43130
        private const val CHANNEL = "control-session"
    }
}
