package app.cadenza.remote.model

import android.os.SystemClock
import androidx.lifecycle.viewModelScope
import app.cadenza.remote.data.ClockSync
import app.cadenza.remote.data.HostProfile
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.counter
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject

// A Bluetooth link needs its bootstrap pings (see RemoteModelFrames) before it can stamp a command.
private const val CLOCK_READY_WAIT_MS = 3_000L
private const val CLOCK_POLL_MS = 50L

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
        // A link that has just connected has not had its first clock replies yet. A tap waits briefly for them.
        withTimeoutOrNull(CLOCK_READY_WAIT_MS) { while (!clock.ready) delay(CLOCK_POLL_MS) }
        // A repeated tap while the same control's command is unanswered is the same intent, so it is dropped.
        if (pending.values.any { it.key == key && !it.unconfirmed }) return
        val command =
            Wire
                .frame("command")
                .put("command_id", id())
                .put("host_epoch", snapshot.hostEpoch)
                .put("expires_at_host_ms", clock.deadline(SystemClock.elapsedRealtime(), deadlineWindow(action)))
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

private fun deadlineWindow(action: JSONObject): Long =
    if (action.optString("kind").startsWith("playback.")) ClockSync.TRANSPORT_WINDOW_MS else ClockSync.DEFAULT_WINDOW_MS

// The Host normally answers within about a second, and the optimistic intent covers that wait. Past a second the
// Remote asks for the request's status every second. The "outcome unknown" notice appears only when the Host itself
// reports the outcome unconfirmed and still has no answer after a grace period: the Host gives the same answer for a
// command it is still applying, which usually resolves within a second or two. Silence from the Host shows nothing;
// the intent just stops being predicted once it is old, and the Host's snapshot shows what happened.
internal fun RemoteModel.trackPending(
    command: JSONObject,
    key: String,
    intent: OptimisticIntent?,
) {
    val commandId = command.getString("command_id")
    val timer =
        viewModelScope.launch {
            while (true) {
                delay(STATUS_QUERY_MS)
                val item = pending[commandId] ?: return@launch
                val age = SystemClock.elapsedRealtime() - item.trackedAtElapsedMs
                queryRequest(commandId)
                if (item.hostUnconfirmed) {
                    warnUnconfirmedIfDue(item)
                } else if (age >= INTENT_LIFETIME_MS && !item.unconfirmed) {
                    item.unconfirmed = true
                    publishOptimisticInternal()
                }
                if (age >= GIVE_UP_MS) {
                    giveUpPending(commandId)
                    return@launch
                }
            }
        }
    pending[commandId] = PendingCommand(command, key, timer, intent)
    publishOptimisticInternal()
}

internal fun RemoteModel.warnUnconfirmedIfDue(item: PendingCommand) {
    if (item.warned || SystemClock.elapsedRealtime() - item.trackedAtElapsedMs < UNCONFIRMED_GRACE_MS) return
    item.warned = true
    item.unconfirmed = true
    publishOptimisticInternal()
    showWarning(UNCONFIRMED_MESSAGE)
}

// Past the give-up window the Remote stops asking. A Host that answered unconfirmed keeps that receipt and repeats it on
// every query, so its row is dropped and reconnects stop replaying the command. A command the Host never answered keeps
// its row, so the next connection still asks for its outcome.
internal suspend fun RemoteModel.giveUpPending(commandId: String) {
    val item = pending[commandId] ?: return
    if (item.hostUnconfirmed) {
        finishCommand(commandId)
    } else {
        pending.remove(commandId)
    }
}

private const val STATUS_QUERY_MS = 1_000L
private const val UNCONFIRMED_GRACE_MS = 3_000L
private const val INTENT_LIFETIME_MS = 10_000L
private const val GIVE_UP_MS = 30_000L

internal fun RemoteModel.optimisticIntents(): List<OptimisticIntent> = pending.values.filterNot { it.unconfirmed }.mapNotNull { it.intent }

// Publishes the Host's last snapshot with every unanswered intent applied on top of it.
internal fun RemoteModel.publishOptimisticInternal() {
    val host = hostSnapshot ?: return
    mutable.update { it.copy(snapshot = host.withOptimisticIntents(optimisticIntents())) }
}
