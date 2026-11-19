package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import org.json.JSONObject

// Reorder and remove for one request in Up next. Host settings decide whose requests this Remote may change.
@Composable
internal fun QueueEntryControls(
    model: RemoteModel,
    state: RemoteState,
    entryId: String,
    modifier: Modifier = Modifier,
) {
    val snapshot = state.snapshot ?: return
    val entries = snapshot.queue
    val index = entries.indexOfFirst { it.id == entryId }
    if (index < 0) return
    val entry = entries[index]
    if (entry.requestedBy == null) return
    val own = entry.requestedBy == state.profile?.remoteId
    val mayChange: (String?) -> Boolean = { owner -> owner != null && (snapshot.allowCrossRemoteEdits || owner == state.profile?.remoteId) }
    val editable = state.connected && snapshot.synchronized && mayChange(entry.requestedBy)
    val previous = entries.getOrNull(index - 1)
    val next = entries.getOrNull(index + 1)
    val key = "queue:$entryId"
    Surface(modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                "Requested by " + if (own) "you" else entry.requesterName,
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                "Length " + duration(entry.song.durationMs) + " · Wait ≈ " + duration(entry.estimatedWaitMs),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(
                    onClick = {
                        model.command(
                            JSONObject().put("kind", "queue.move").put("entry_id", entry.id).put("before_entry_id", previous?.id),
                            key,
                        )
                    },
                    enabled = editable && previous != null && mayChange(previous.requestedBy),
                ) { Icon(cadenzaVector(CadenzaIcon.UP), "Move " + entry.song.title + " earlier") }
                IconButton(
                    onClick = {
                        model.command(
                            JSONObject().put("kind", "queue.move").put("entry_id", next?.id).put("before_entry_id", entry.id),
                            key,
                        )
                    },
                    enabled = editable && next != null && mayChange(next.requestedBy),
                ) { Icon(cadenzaVector(CadenzaIcon.DOWN), "Move " + entry.song.title + " later") }
                TextButton(
                    onClick = { model.command(JSONObject().put("kind", "queue.remove").put("entry_id", entry.id), key) },
                    enabled = editable,
                ) { Text("Remove") }
            }
        }
    }
}
