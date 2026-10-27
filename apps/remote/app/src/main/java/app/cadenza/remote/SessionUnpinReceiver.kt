package app.cadenza.remote

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class SessionUnpinReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        (context.applicationContext as CadenzaApplication).unpinSession?.invoke()
        SessionNotification(context).clear()
    }
}
