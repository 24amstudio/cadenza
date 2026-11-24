package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import app.cadenza.remote.data.SongIdentity
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.model.receiveSharedTrack
import org.json.JSONObject

/** Asks what to do with a song shared from Apple Music. Play now needs the person to be allowed to interrupt. */
@Composable
internal fun SharedTrackDialog(
    model: RemoteModel,
    identity: SongIdentity,
    state: RemoteState,
) {
    val current = state.snapshot?.current
    val key = "shared:" + identity.source + ":" + identity.id
    val canInterrupt = mayInterruptPlayback(state)

    fun send(kind: String) {
        val action = JSONObject().put("kind", kind).put("song", identity.json())
        if (kind == "queue.play_now") action.put("occurrence_id", current?.occurrenceId ?: JSONObject.NULL)
        model.command(action, key)
        model.receiveSharedTrack(null)
    }

    AlertDialog(
        onDismissRequest = { model.receiveSharedTrack(null) },
        title = { Text("Shared song") },
        text = {
            Column {
                Text("Cadenza Host will find this song in Apple Music and send it to your Mac.")
                TextButton(onClick = { send("queue.play_next") }, enabled = state.connected) { Text("Play next") }
                TextButton(onClick = { send("queue.enqueue") }, enabled = state.connected) { Text("Add to queue") }
            }
        },
        confirmButton = {
            TextButton(onClick = { send("queue.play_now") }, enabled = state.connected && canInterrupt) {
                Text("Play now")
            }
        },
        dismissButton = {
            TextButton(onClick = { model.receiveSharedTrack(null) }) { Text("Cancel") }
        },
    )
}
