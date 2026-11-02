package app.cadenza.remote.media

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Keeps the Remote process, and its control connection, alive while Host playback is active. Android reclaims
 * background processes quickly, and a reclaimed process drops the socket that delivers song changes.
 */
class PlaybackKeepAlive(
    private val context: Context,
) {
    private var running = false

    /** Returns false when Android refuses to start the service from the background. */
    fun update(active: Boolean): Boolean {
        if (active == running) return true
        val intent = Intent(context, PlaybackKeepAliveService::class.java)
        if (!active) {
            running = false
            return try {
                context.startService(intent.setAction(PlaybackKeepAliveService.ACTION_STOP))
                true
            } catch (error: IllegalStateException) {
                false
            }
        }
        return try {
            ContextCompat.startForegroundService(context, intent)
            running = true
            true
        } catch (error: IllegalStateException) {
            false
        }
    }
}

/**
 * Runs in the foreground with the session notification, so the notification stays the one the user already sees.
 * Stopping detaches the notification instead of removing it, because the session still exists while it is paused.
 */
class PlaybackKeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        if (intent?.action == ACTION_STOP) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
            stopSelf()
            return START_NOT_STICKY
        }
        val notification: Notification =
            SessionNotification.lastNotification ?: SessionNotification.placeholder(this)
        ServiceCompat.startForeground(
            this,
            SessionNotification.ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
        )
        return START_NOT_STICKY
    }

    companion object {
        const val ACTION_STOP = "app.cadenza.remote.media.STOP_PLAYBACK_KEEP_ALIVE"
    }
}
