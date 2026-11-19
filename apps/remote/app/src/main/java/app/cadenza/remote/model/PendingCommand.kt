package app.cadenza.remote.model

import android.os.SystemClock
import kotlinx.coroutines.Job
import org.json.JSONObject

internal data class PendingCommand(
    val frame: JSONObject,
    val key: String,
    val timer: Job,
    val intent: OptimisticIntent?,
    var sentAtElapsedMs: Long = 0,
    // Set when the intent stops applying: the Host reported the outcome unknown for long enough that the Remote says so,
    // or it answered nothing for so long that the Host's own snapshot is the better guide. The record stays so a
    // later status answer can still settle it.
    var unconfirmed: Boolean = false,
    // The Host answered "unconfirmed". That also covers a command it is still applying, so it is not shown yet.
    var hostUnconfirmed: Boolean = false,
    var warned: Boolean = false,
    val trackedAtElapsedMs: Long = SystemClock.elapsedRealtime(),
)
