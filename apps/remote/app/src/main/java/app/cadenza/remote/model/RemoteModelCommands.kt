package app.cadenza.remote.model

import android.os.SystemClock
import androidx.lifecycle.viewModelScope
import app.cadenza.remote.data.HostProfile
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.counter
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

// Commands take effect on screen at once. The Host's result confirms them later, or reverts them with a reason.
internal suspend fun RemoteModel.sendCommand(
    action: JSONObject,
    key: String,
    song: Song? = null,
) {
    var createdId: String? = null
    var createdProfile: HostProfile? = null
    var sent = false
    try {
        val session = generation
        val transport = requireNotNull(connection) { "Reconnect before sending this request." }
        val profile = requireNotNull(mutable.value.profile)
        createdProfile = profile
        val snapshot = requireNotNull(mutable.value.snapshot) { "Wait for Host state." }
        check(mutable.value.connected && !isStale()) { "Reconnect and wait for current Host state." }
        // A repeated tap while the same control's command is unanswered is the same intent, so it is dropped.
        if (pending.values.any { it.key == key && !it.unconfirmed }) return
        val command =
            Wire
                .frame("command")
                .put("command_id", id())
                .put("host_epoch", snapshot.hostEpoch)
                .put("expires_at_host_ms", clock.deadline(SystemClock.elapsedRealtime()))
                .put("expected_revision", snapshot.revision)
                .put("action", action)
        val commandId = command.getString("command_id")
        createdId = commandId
        check(pending.size < 32) { "Too many requests are waiting for Cadenza Host. Try again shortly." }
        val appliedAt = clock.hostTime(SystemClock.elapsedRealtime())
        trackPending(command, key, optimisticIntent(command, profile.remoteId, song, appliedAt))
        reportLog("info", "command.sent", "kind=${action.optString("kind")} command_id=$commandId key=$key")
        withContext(ioDispatcher) { app.database.savePending(profile, command, key) }
        check(
            session == generation && transport === connection && mutable.value.profile == profile &&
                (foreground || key.startsWith("playback.")) && mutable.value.connected,
        ) {
            "The connection changed while saving this request. Review the current queue before retrying."
        }
        check(
            clock.hostTime(SystemClock.elapsedRealtime()) < command.counter("expires_at_host_ms"),
        ) { "This request expired before it was sent." }
        pending[commandId]?.sentAtElapsedMs = SystemClock.elapsedRealtime()
        sent = transport.send(command)
        check(sent) { "The connection closed before the request was sent." }
    } catch (error: Exception) {
        if (!sent && createdId != null) {
            pending.remove(createdId)?.timer?.cancel()
            publishOptimisticInternal()
            val profile = createdProfile
            val failedId = createdId
            if (profile != null) withContext(ioDispatcher) { app.database.finishPending(profile, failedId) }
        }
        showWarning(error.message ?: "This request was not sent. Reconnect and try again.")
    }
}

// The Host normally answers within about a second. Past that the Remote asks for the status of the request.
// After a grace period it stops showing the intent and says so. Either way it never blocks the screen.
internal fun RemoteModel.trackPending(
    command: JSONObject,
    key: String,
    intent: OptimisticIntent?,
) {
    val commandId = command.getString("command_id")
    val timer =
        viewModelScope.launch {
            delay(1_000)
            if (pending.containsKey(commandId)) queryRequest(commandId)
            delay(4_000)
            val item = pending[commandId] ?: return@launch
            if (item.unconfirmed) return@launch
            item.unconfirmed = true
            publishOptimisticInternal()
            showWarning(UNCONFIRMED_MESSAGE)
        }
    pending[commandId] = PendingCommand(command, key, timer, intent)
    publishOptimisticInternal()
}

internal fun RemoteModel.optimisticIntents(): List<OptimisticIntent> = pending.values.filterNot { it.unconfirmed }.mapNotNull { it.intent }

// Publishes the Host's last snapshot with every unanswered intent applied on top of it.
internal fun RemoteModel.publishOptimisticInternal() {
    val host = hostSnapshot ?: return
    mutable.update { it.copy(snapshot = host.withOptimisticIntents(optimisticIntents())) }
}
