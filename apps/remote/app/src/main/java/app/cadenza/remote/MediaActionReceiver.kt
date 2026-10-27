package app.cadenza.remote

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class MediaActionReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val action = intent.getStringExtra(ACTION) ?: return
        val app = context.applicationContext as CadenzaApplication
        app.mediaAction?.invoke(action)
            ?: context.startActivity(
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            )
    }

    companion object {
        const val ACTION = "app.cadenza.remote.MEDIA_ACTION"
    }
}
