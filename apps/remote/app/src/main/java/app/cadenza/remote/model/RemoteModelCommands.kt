package app.cadenza.remote.model

import android.os.SystemClock
import androidx.lifecycle.viewModelScope
import app.cadenza.remote.data.HostProfile
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.counter
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

internal suspend fun RemoteModel.sendCommand(
    action: JSONObject,
    key: String,
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
        check(key !in mutable.value.pending && pending.values.none { it.key == key }) {
            "This request is still pending. Check its original outcome before retrying."
        }
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
        check(pending.size < 32) { "Resolve earlier unconfirmed requests before sending more." }
        mutable.update { it.copy(pending = it.pending + key) }
        val timer =
            viewModelScope.launch {
                delay(1_000)
                if (session == generation && foreground && pending.containsKey(commandId)) {
                    mutable.update {
                        it.copy(
                            pending = it.pending - key,
                            prompt =
                                Prompt(
                                    "Request unconfirmed",
                                    "Host did not confirm this request within one second. Check the original request before retrying.",
                                    commandId,
                                ),
                        )
                    }
                    queryRequest(commandId)
                    connection?.send(Wire.frame("state.get").put("request_id", id()))
                }
            }
        pending[commandId] = PendingCommand(command, key, timer)
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
            mutable.update { it.copy(pending = pending.values.map { item -> item.key }.toSet()) }
            val profile = createdProfile
            val failedId = createdId
            if (profile != null) withContext(ioDispatcher) { app.database.finishPending(profile, failedId) }
        }
        showError("Action unavailable", error.message ?: "Reconnect and retry.")
    }
}
