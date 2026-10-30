package app.cadenza.remote

import android.os.SystemClock
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.nullableString
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import org.json.JSONObject

internal fun RemoteModel.checkRequestInternal(commandId: String) {
    statusChecks.add(commandId)
    queryRequest(commandId)
    dismissPrompt()
    mutable.update { it.copy(notice = Notice("Checking request status")) }
}

internal fun RemoteModel.queryRequest(commandId: String) {
    if (pending.containsKey(commandId)) {
        connection?.send(Wire.frame("command.status").put("command_id", commandId).put("request_id", id()))
    }
}

internal suspend fun RemoteModel.commandResultInternal(frame: JSONObject) {
    val commandId = frame.getString("command_id")
    val original = pending[commandId] ?: return
    if (frame.nullableString("host_epoch") != mutable.value.snapshot?.hostEpoch) return
    original.timer.cancel()
    val sentAt = original.sentAtElapsedMs
    if (sentAt > 0) {
        mutable.update { it.copy(lastCommandLatencyMs = (SystemClock.elapsedRealtime() - sentAt).coerceAtLeast(0)) }
    }
    when (frame.getString("outcome")) {
        "applied" -> {
            statusChecks.remove(commandId)
            val profile = mutable.value.profile
            if (profile != null) withContext(updateDispatcher) { updateApp.database.finishPending(profile, commandId) }
            pending.remove(commandId)
            mutable.update { it.copy(pending = it.pending - original.key, notice = Notice("Request applied")) }
        }
        "unconfirmed" -> {
            val showPrompt = statusChecks.remove(commandId)
            val resolved = frame.optBoolean("resolved", false)
            if (resolved) {
                val profile = mutable.value.profile
                if (profile != null) withContext(updateDispatcher) { updateApp.database.finishPending(profile, commandId) }
                pending.remove(commandId)
                mutable.update { it.copy(pending = it.pending - original.key) }
            }
            mutable.update {
                val message = frame.optString("message", "Check this request after Host reconciles Music.")
                if (showPrompt || !resolved) {
                    it.copy(
                        pending = it.pending - original.key,
                        prompt = Prompt("Request unconfirmed", message, if (resolved) null else commandId),
                    )
                } else {
                    it.copy(pending = it.pending - original.key, notice = Notice("Request still needs confirmation"))
                }
            }
        }
        else -> {
            statusChecks.remove(commandId)
            val profile = mutable.value.profile
            if (profile != null) withContext(updateDispatcher) { updateApp.database.finishPending(profile, commandId) }
            pending.remove(commandId)
            mutable.update { it.copy(pending = it.pending - original.key) }
            showError("Request blocked", frame.optString("message", "The queue changed or Host settings protect this request."))
        }
    }
}

internal fun RemoteModel.operationErrorInternal(frame: JSONObject) {
    val request = frame.nullableString("request_id")
    val message = frame.optString("message", "The operation failed.")
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
        if (lyricUserInitiated) showError("Lyrics unavailable", message)
        lyricUserInitiated = false
    } else {
        showError("Action unavailable", message)
    }
    if (frame.optString("error_code") in listOf("authentication", "revoked")) disconnect()
}

internal fun RemoteModel.isStaleInternal(now: Long = SystemClock.elapsedRealtime()): Boolean =
    !mutable.value.connected || now - maxOf(mutable.value.lastStateAt, lastHeartbeatAt) > 3_000

internal fun RemoteModel.positionInternal(now: Long): Long =
    mutable.value.snapshot?.let { clock.position(it, now, isStaleInternal(now)) } ?: 0

internal fun RemoteModel.monitorSongInternal() {
    mutable.update {
        it.copy(
            sessionActive = true,
            monitoringSong = true,
            notice = Notice("Song status monitoring is on until you unpin it"),
        )
    }
}

internal fun RemoteModel.endSessionStatusInternal() {
    mutable.update { it.copy(sessionActive = false, monitoringSong = false) }
    if (!foreground) {
        networkMonitor.close()
        discovery?.close()
        discovery = null
        disconnect()
    }
}

internal fun RemoteModel.maintainBackgroundSessionInternal() =
    foreground || mutable.value.monitoringSong || mutable.value.snapshot?.playing == true
