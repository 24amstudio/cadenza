package app.cadenza.remote

import android.os.SystemClock
import org.json.JSONObject

    private fun pingClock() {
        lastClockSentAt = SystemClock.elapsedRealtime()
        connection?.send(
            Wire
                .frame("clock")
                .put("request_id", id())
                .put("clock", JSONObject().put("sent_at_remote_ms", SystemClock.elapsedRealtime())),
        )
    }

