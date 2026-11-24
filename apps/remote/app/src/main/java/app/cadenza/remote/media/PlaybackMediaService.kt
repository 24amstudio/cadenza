package app.cadenza.remote.media

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import app.cadenza.remote.CadenzaApplication

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
        val intent = Intent(context, PlaybackMediaService::class.java)
        if (!active) {
            running = false
            return try {
                context.startService(intent.setAction(PlaybackMediaService.ACTION_STOP))
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
 * The media foreground service. It keeps the session notification foreground while Host plays. Widget transport taps
 * arrive as a PendingIntent.getForegroundService, so a tap never opens an Activity. A tap with no session in memory
 * only shows the foreground notification briefly and then leaves.
 */
class PlaybackMediaService : Service() {
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
        // Android requires startForeground soon after a foreground start, so it happens before any transport is handled.
        ServiceCompat.startForeground(
            this,
            SessionNotification.ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
        )
        intent?.getStringExtra(EXTRA_TRANSPORT)?.let { action ->
            (application as CadenzaApplication).mediaAction?.invoke(action)
            if (SessionNotification.lastNotification == null) {
                ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    companion object {
        const val ACTION_STOP = "app.cadenza.remote.media.STOP_PLAYBACK_KEEP_ALIVE"
        const val EXTRA_TRANSPORT = "app.cadenza.remote.media.TRANSPORT"
    }
}
