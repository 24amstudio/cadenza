package app.cadenza.remote.updates

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import app.cadenza.remote.CadenzaApplication
import app.cadenza.remote.MainActivity
import app.cadenza.remote.R

class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val app = context.applicationContext as CadenzaApplication
        val handler = app.installationHandler
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_SUCCESS -> {
                app.updateSettings.write("staged" to null, "installation_session" to null)
                handler?.invoke(null)
            }
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmation = confirmation(intent)
                if (handler != null && confirmation != null) handler(confirmation) else notifyReady(context, confirmation)
            }
            else -> {
                app.updateSettings.write(
                    "installation_session" to null,
                    "installation_error" to
                        (intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "Installation failed. Retry from Settings."),
                )
                if (handler != null) handler(null) else notifyReady(context, null)
            }
        }
    }

    private fun confirmation(intent: Intent): Intent? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java) else legacyConfirmation(intent)

    // Older Android-compatible Huawei firmware uses the untyped Parcelable accessor.
    @Suppress("DEPRECATION")
    private fun legacyConfirmation(intent: Intent): Intent? = intent.getParcelableExtra(Intent.EXTRA_INTENT)

    companion object {
        fun notifyReady(
            context: Context,
            confirmation: Intent?,
        ) {
            val intent = confirmation ?: Intent(context, MainActivity::class.java)
            val pending =
                PendingIntent.getActivity(
                    context,
                    43128,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel("updates", context.getString(R.string.update_channel), NotificationManager.IMPORTANCE_DEFAULT),
            )
            if (Build.VERSION.SDK_INT >= 33 &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) {
                return
            }
            val notification =
                NotificationCompat
                    .Builder(context, "updates")
                    .setSmallIcon(android.R.drawable.stat_sys_download_done)
                    .setContentTitle(context.getString(R.string.update_ready))
                    .setContentText(context.getString(R.string.update_confirm))
                    .setContentIntent(pending)
                    .setAutoCancel(true)
                    .build()
            manager.notify(43128, notification)
        }
    }
}
