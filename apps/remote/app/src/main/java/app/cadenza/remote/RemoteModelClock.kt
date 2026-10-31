package app.cadenza.remote

import android.os.SystemClock
import app.cadenza.remote.data.Wire
import org.json.JSONObject

internal fun RemoteModel.pingClock() {
    lastClockSentAt = SystemClock.elapsedRealtime()
    connection?.send(
        Wire
            .frame("clock")
            .put("request_id", id())
            .put("clock", JSONObject().put("sent_at_remote_ms", SystemClock.elapsedRealtime())),
    )
}
