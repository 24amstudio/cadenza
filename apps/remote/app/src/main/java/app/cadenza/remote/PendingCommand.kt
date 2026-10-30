package app.cadenza.remote

import kotlinx.coroutines.Job
import org.json.JSONObject

internal data class PendingCommand(
    val frame: JSONObject,
    val key: String,
    val timer: Job,
    var sentAtElapsedMs: Long = 0,
)
