package app.cadenza.remote.model

import kotlinx.coroutines.Job
import org.json.JSONObject

internal data class PendingCommand(
    val frame: JSONObject,
    val key: String,
    val timer: Job,
    val intent: OptimisticIntent?,
    var sentAtElapsedMs: Long = 0,
    // Set when the Host has not answered in time. The intent stops applying, but the record stays so a
    // later status answer can still settle it.
    var unconfirmed: Boolean = false,
)
