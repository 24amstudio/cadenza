package app.cadenza.remote.model

import android.os.SystemClock
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.nullableString
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import org.json.JSONObject

internal const val UNCONFIRMED_MESSAGE = "Music may still apply this request. Cadenza is checking."

internal fun RemoteModel.queryRequest(commandId: String) {
    if (pending.containsKey(commandId)) {
        connection?.send(Wire.frame("command.status").put("command_id", commandId).put("request_id", id()))
    }
}

internal suspend fun RemoteModel.commandResultInternal(frame: JSONObject) {
    val commandId = frame.getString("command_id")
    val original = pending[commandId] ?: return
    if (frame.nullableString("host_epoch") != hostSnapshot?.hostEpoch) return
    original.timer.cancel()
    reportLog(
        "info",
        "command.result",
        "command_id=$commandId outcome=${frame.optString("outcome")} error=${frame.optString("error_code")}",
    )
    val sentAt = original.sentAtElapsedMs
    if (sentAt > 0) {
        mutable.update { it.copy(lastCommandLatencyMs = (SystemClock.elapsedRealtime() - sentAt).coerceAtLeast(0)) }
    }
    when (frame.getString("outcome")) {
        "applied" -> finishCommand(commandId)
        "unconfirmed" ->
            if (frame.optBoolean("resolved", false)) {
                finishCommand(commandId)
            } else {
                // Keep the record so a later status answer can still settle it, but stop showing the intent.
                original.unconfirmed = true
                publishOptimisticInternal()
                showWarning(UNCONFIRMED_MESSAGE)
            }
        else -> {
            finishCommand(commandId)
            reportFailure(
                frame.nullableString("error_code"),
                "Request blocked",
                frame.optString("message", "The queue changed or Host settings protect this request."),
            )
        }
    }
}

private suspend fun RemoteModel.finishCommand(commandId: String) {
    val profile = mutable.value.profile
    if (profile != null) withContext(updateDispatcher) { updateApp.database.finishPending(profile, commandId) }
    pending.remove(commandId)
    publishOptimisticInternal()
}

internal fun RemoteModel.operationErrorInternal(frame: JSONObject) {
    val request = frame.nullableString("request_id")
    val message = frame.optString("message", "The operation failed.")
    val code = frame.nullableString("error_code")
    if (request != null && request == searchId) {
        searchTimeout?.cancel()
        mutable.update { it.copy(searching = false) }
    }
    if (request != null && request == preparationId) {
        preparationTimeout?.cancel()
        mutable.update { it.copy(preparing = false) }
    }
    if (request != null && request == lyricRequestId) {
        lyricsTimeout?.cancel()
        mutable.update { it.copy(lyricsLoading = false, lyricsIssue = message) }
        if (lyricUserInitiated) reportFailure(code, "Lyrics unavailable", message)
        lyricUserInitiated = false
    } else {
        reportFailure(code, "Action unavailable", message)
    }
    if (frame.optString("error_code") in listOf("authentication", "revoked")) disconnect()
}

internal fun RemoteModel.isStaleInternal(now: Long = SystemClock.elapsedRealtime()): Boolean =
    !mutable.value.connected || now - maxOf(mutable.value.lastStateAt, lastHeartbeatAt) > 3_000

internal fun RemoteModel.positionInternal(now: Long): Long =
    mutable.value.snapshot?.let { clock.position(it, now, isStaleInternal(now)) } ?: 0

internal fun RemoteModel.endSessionStatusInternal() {
    mutable.update { it.copy(sessionActive = false) }
    if (!foreground) {
        networkMonitor.close()
        discovery?.close()
        discovery = null
        disconnect()
    }
}

// A playing Host keeps the session pinned automatically, so backgrounding never drops a song that is playing.
internal fun RemoteModel.maintainBackgroundSessionInternal() = foreground || mutable.value.snapshot?.playing == true
