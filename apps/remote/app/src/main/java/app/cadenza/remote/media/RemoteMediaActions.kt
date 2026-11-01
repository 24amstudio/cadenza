package app.cadenza.remote.media

import app.cadenza.remote.model.RemoteState
import org.json.JSONObject

class RemoteMediaActions(
    private val state: () -> RemoteState,
    private val command: (JSONObject, String) -> Unit,
) {
    fun sessionState(value: RemoteState): MediaSessionState {
        val current = value.snapshot?.current
        val canInterrupt =
            current?.requestedBy == null || current.requestedBy == value.profile?.remoteId || value.snapshot.allowCrossRemoteEdits
        return MediaSessionState(
            active = value.connected && current != null,
            playing = value.snapshot?.playing == true,
            title = current?.song?.title.orEmpty(),
            artist = current?.song?.artist.orEmpty(),
            album = current?.song?.album.orEmpty(),
            artworkUrl = current?.song?.artworkUrl,
            artworkBytes = current?.song?.artworkUrl?.let { value.artwork[it] },
            occurrenceId = current?.occurrenceId.orEmpty(),
            positionMs = current?.positionMs ?: 0,
            durationMs = current?.song?.durationMs,
            canInterrupt = canInterrupt,
        )
    }

    fun handle(action: String) {
        val currentState = state()
        val current = currentState.snapshot?.current ?: return
        if (!currentState.connected) return
        val canInterrupt =
            current.requestedBy == null || current.requestedBy == currentState.profile?.remoteId ||
                currentState.snapshot.allowCrossRemoteEdits
        when {
            action == "play" -> command(playback("resume", current.occurrenceId), "playback.resume")
            action == "pause" -> command(playback("pause", current.occurrenceId), "playback.pause")
            action == "next" && canInterrupt -> command(playback("skip", current.occurrenceId), "playback.skip")
            action == "previous" && canInterrupt -> command(playback("previous", current.occurrenceId), "playback.previous")
            action.startsWith("seek:") && canInterrupt -> {
                val position = action.substringAfter(':').toLongOrNull() ?: return
                command(playback("seek", current.occurrenceId).put("position_ms", position), "playback.seek")
            }
        }
    }

    private fun playback(
        kind: String,
        occurrenceId: String,
    ): JSONObject = JSONObject().put("kind", "playback.$kind").put("occurrence_id", occurrenceId)
}
