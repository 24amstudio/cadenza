package app.cadenza.remote.model

import android.os.SystemClock
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.nullableString
import app.cadenza.remote.network.HostLivenessPolicy
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
    // The command ID is unique to this Remote and the connection reaches one Host process, so the answer is trusted
    // even when the Host restarted since the last snapshot. Dropping it left the command unanswered until it timed out.
    reportLog(
        "info",
        "command.result",
        "command_id=$commandId outcome=${frame.optString("outcome")} error=${frame.optString("error_code")}",
    )
    val sentAt = original.sentAtElapsedMs
    if (sentAt > 0) {
        val durationMs = (SystemClock.elapsedRealtime() - sentAt).coerceAtLeast(0)
        mutable.update { it.copy(lastCommandLatencyMs = durationMs) }
        reportLog(
            "info",
            "performance.command",
            "kind=${original.key} duration_ms=$durationMs outcome=${frame.optString("outcome")}",
        )
    }
    when (frame.getString("outcome")) {
        "applied" -> finishCommand(commandId)
        "unconfirmed" ->
            if (frame.optBoolean("resolved", false)) {
                finishCommand(commandId)
            } else {
                // The Host answers "unconfirmed" for a command it is still applying too, so the tracker keeps
                // asking for its status and warns only if the answer stays unknown past the grace period.
                original.hostUnconfirmed = true
                warnUnconfirmedIfDue(original)
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

// The Host could not decode a command, so it refused it before anything ran. The refusal names the command and carries no
// host_epoch; command IDs are unique to this Remote's pending commands, so the refusal settles that command directly.
internal suspend fun RemoteModel.commandRefusedInternal(frame: JSONObject): Boolean {
    val commandId = frame.nullableString("command_id") ?: return false
    val original = pending[commandId] ?: return false
    original.timer.cancel()
    reportLog(
        "info",
        "command.result",
        "command_id=$commandId outcome=rejected error=${frame.optString("error_code")}",
    )
    finishCommand(commandId)
    reportFailure(
        frame.nullableString("error_code"),
        "Request blocked",
        frame.optString("message", "The queue changed or Host settings protect this request."),
    )
    return true
}

private suspend fun RemoteModel.finishCommand(commandId: String) {
    val profile = mutable.value.profile
    if (profile != null) withContext(updateDispatcher) { updateApp.database.finishPending(profile, commandId) }
    pending.remove(commandId)?.timer?.cancel()
    publishOptimisticInternal()
}

internal fun RemoteModel.operationErrorInternal(frame: JSONObject) {
    if (applyBrowseError(frame)) return
    val request = frame.nullableString("request_id")
    val message = frame.optString("message", "The operation failed.")
    val code = frame.nullableString("error_code")
    if (request != null && request == searchId) {
        searchTimeout?.cancel()
        mutable.update { it.copy(searching = false) }
    }
    if (request != null && request == favoriteResolveId) failFavoriteResolution("Music could not look up this song. Try again.")
    if (request != null && request == preparationId) {
        preparationTimeout?.cancel()
        preparingIdentity = null
        mutable.update { it.copy(preparing = false) }
    }
    if (request != null && request == lyricRequestId) {
        lyricsTimeout?.cancel()
        recordLyricsDuration()
        mutable.update { it.copy(lyricsLoading = false, lyricsIssue = message) }
        if (lyricUserInitiated) reportFailure(code, "Lyrics unavailable", message)
        lyricUserInitiated = false
    } else {
        reportFailure(code, "Action unavailable", message)
    }
    if (frame.optString("error_code") in listOf("authentication", "revoked")) disconnect()
}

internal fun RemoteModel.isStaleInternal(now: Long = SystemClock.elapsedRealtime()): Boolean =
    !mutable.value.connected || now - maxOf(mutable.value.lastStateAt, lastHeartbeatAt) > HostLivenessPolicy.staleAfterMs(transportMode)

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
