package app.cadenza.remote.model

import app.cadenza.remote.data.HostSnapshot
import app.cadenza.remote.data.QueueEntry
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.counter
import app.cadenza.remote.data.nullableString
import org.json.JSONObject

// The Remote shows the result it expects while a command is unanswered. The Host's snapshot stays the
// source of truth: an intent applies only until its command is answered, so a rejected or expired command
// reverts when its result arrives.
internal sealed interface OptimisticIntent {
    data class Playing(
        val playing: Boolean,
    ) : OptimisticIntent

    data class Volume(
        val percent: Int,
    ) : OptimisticIntent

    data class Seek(
        val occurrenceId: String,
        val positionMs: Long,
        val appliedAtHostMs: Long,
    ) : OptimisticIntent

    data class Remove(
        val entryId: String,
    ) : OptimisticIntent

    data class Move(
        val entryId: String,
        val beforeEntryId: String?,
    ) : OptimisticIntent

    data class Enqueue(
        val commandId: String,
        val song: Song,
        val requestedBy: String,
        val next: Boolean,
    ) : OptimisticIntent
}

// Skip, previous, and play now have no safe local prediction: the next occurrence exists only once Music
// reports it. Those commands return null and wait for the Host's snapshot.
internal fun optimisticIntent(
    command: JSONObject,
    requestedBy: String,
    song: Song?,
    appliedAtHostMs: Long?,
): OptimisticIntent? {
    val action = command.optJSONObject("action") ?: return null
    val kind = action.optString("kind")
    return when (kind) {
        "playback.pause" -> OptimisticIntent.Playing(false)
        "playback.resume" -> OptimisticIntent.Playing(true)
        "playback.volume" -> OptimisticIntent.Volume(action.optInt("percent"))
        "playback.seek" -> {
            val occurrence = action.nullableString("occurrence_id")
            if (occurrence == null || appliedAtHostMs == null) {
                null
            } else {
                OptimisticIntent.Seek(occurrence, action.counter("position_ms"), appliedAtHostMs)
            }
        }
        "queue.remove" -> OptimisticIntent.Remove(action.getString("entry_id"))
        "queue.move" -> OptimisticIntent.Move(action.getString("entry_id"), action.nullableString("before_entry_id"))
        "queue.enqueue", "queue.play_next" ->
            song?.let {
                OptimisticIntent.Enqueue(
                    commandId = command.getString("command_id"),
                    song = it,
                    requestedBy = requestedBy,
                    next = kind == "queue.play_next",
                )
            }
        else -> null
    }
}

internal fun HostSnapshot.withOptimisticIntents(intents: List<OptimisticIntent>): HostSnapshot =
    intents.fold(this) { snapshot, intent -> snapshot.applying(intent) }

private fun HostSnapshot.applying(intent: OptimisticIntent): HostSnapshot =
    when (intent) {
        is OptimisticIntent.Playing -> copy(playing = intent.playing)
        is OptimisticIntent.Volume -> copy(volume = intent.percent)
        is OptimisticIntent.Seek -> {
            val playback = current
            if (playback?.occurrenceId == intent.occurrenceId) {
                copy(current = playback.copy(positionMs = intent.positionMs, sampledAtHostMs = intent.appliedAtHostMs))
            } else {
                this
            }
        }
        is OptimisticIntent.Remove -> copy(queue = queue.filterNot { it.id == intent.entryId })
        is OptimisticIntent.Move -> moved(intent)
        is OptimisticIntent.Enqueue -> {
            val entry =
                QueueEntry(
                    id = "pending:" + intent.commandId,
                    requestedBy = intent.requestedBy,
                    requesterName = "",
                    song = intent.song,
                    estimatedWaitMs = null,
                    estimatedStartHostMs = null,
                    estimateStatus = null,
                )
            copy(queue = if (intent.next) listOf(entry) + queue else queue + entry)
        }
    }

private fun HostSnapshot.moved(intent: OptimisticIntent.Move): HostSnapshot {
    val moving = queue.firstOrNull { it.id == intent.entryId } ?: return this
    val rest = queue.filterNot { it.id == intent.entryId }
    // A missing anchor means the row goes to the end, matching the Host's queue.move semantics.
    val index = rest.indexOfFirst { it.id == intent.beforeEntryId }.takeIf { it >= 0 } ?: rest.size
    return copy(queue = rest.take(index) + moving + rest.drop(index))
}
