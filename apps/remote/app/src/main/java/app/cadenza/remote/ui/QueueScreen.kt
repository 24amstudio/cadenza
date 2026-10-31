package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
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

@Composable
fun QueueScreen(
    model: RemoteModel,
    state: RemoteState,
) {
    val snapshot = state.snapshot
    val entries = snapshot?.queue.orEmpty()
    Column(Modifier.fillMaxSize().padding(24.dp)) {
        ScreenHeader("Queue", state)
        if (snapshot?.synchronized == false) {
            Text(snapshot.issue ?: "The queue needs reconciliation in Cadenza Host.", style = MaterialTheme.typography.bodyLarge)
        }
        if (entries.isEmpty()) {
            Text("Queue is empty", style = MaterialTheme.typography.headlineSmall)
            Text("Add a song from Search.")
        }
        LazyColumn(
            Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            itemsIndexed(entries, key = { _, entry -> entry.id }) { index, entry ->
                val own = entry.requestedBy == state.profile?.remoteId
                val editable =
                    state.connected && snapshot?.synchronized == true && entry.requestedBy != null &&
                        (own || snapshot.allowCrossRemoteEdits)
                val previous = entries.getOrNull(index - 1)
                val next = entries.getOrNull(index + 1)
                val mayCrossPrevious =
                    previous?.requestedBy != null &&
                        (snapshot?.allowCrossRemoteEdits == true || previous.requestedBy == state.profile?.remoteId)
                val mayCrossNext =
                    next?.requestedBy != null &&
                        (snapshot?.allowCrossRemoteEdits == true || next.requestedBy == state.profile?.remoteId)
                Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainer) {
                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(entry.song.title, style = MaterialTheme.typography.titleLarge)
                        Text(entry.song.artist, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("Requested by " + if (own) "you" else entry.requesterName)
                        FlowRow(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text("Length " + duration(entry.song.durationMs))
                            Text("Wait ≈ " + duration(entry.estimatedWaitMs))
                        }
                        if (entry.requestedBy != null) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                IconButton(
                                    onClick = {
                                        model.command(
                                            JSONObject()
                                                .put("kind", "queue.move")
                                                .put("entry_id", entry.id)
                                                .put("before_entry_id", previous?.id),
                                            "queue:" + entry.id,
                                        )
                                    },
                                    enabled = editable && mayCrossPrevious && "queue:" + entry.id !in state.pending,
                                ) { Icon(cadenzaVector(CadenzaIcon.UP), "Move " + entry.song.title + " earlier") }
                                IconButton(
                                    onClick = {
                                        model.command(
                                            JSONObject()
                                                .put("kind", "queue.move")
                                                .put("entry_id", next?.id)
                                                .put("before_entry_id", entry.id),
                                            "queue:" + entry.id,
                                        )
                                    },
                                    enabled = editable && mayCrossNext && "queue:" + entry.id !in state.pending,
                                ) { Icon(cadenzaVector(CadenzaIcon.DOWN), "Move " + entry.song.title + " later") }
                                TextButton(
                                    onClick = {
                                        model.command(
                                            JSONObject().put("kind", "queue.remove").put("entry_id", entry.id),
                                            "queue:" + entry.id,
                                        )
                                    },
                                    enabled = editable && "queue:" + entry.id !in state.pending,
                                ) { Text(if ("queue:" + entry.id in state.pending) "Working…" else "Remove") }
                            }
                        }
                    }
                }
            }
        }
        Surface(color = MaterialTheme.colorScheme.surfaceContainerHigh, shape = MaterialTheme.shapes.extraLarge) {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Total remaining ≈ " + duration(snapshot?.totalRemainingMs), style = MaterialTheme.typography.titleLarge)
                Text(
                    if (snapshot?.playing ==
                        false
                    ) {
                        "Paused"
                    } else {
                        "Estimates exclude unobserved AutoMix overlap."
                    },
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
}
