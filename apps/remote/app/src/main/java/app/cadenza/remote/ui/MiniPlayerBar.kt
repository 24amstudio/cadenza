package app.cadenza.remote.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import org.json.JSONObject

@Composable
internal fun MiniPlayerBar(
    model: RemoteModel,
    state: RemoteState,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val current = state.snapshot?.current ?: return
    val playing = state.snapshot.playing
    Surface(
        modifier = modifier.padding(horizontal = 12.dp, vertical = 8.dp),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        tonalElevation = 4.dp,
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable(onClick = onOpen)
                .semantics { role = Role.Button }
                .padding(start = 8.dp, end = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Artwork(current.song.artworkUrl, Modifier.size(44.dp))
            androidx.compose.foundation.layout.Column(Modifier.weight(1f)) {
                Text(current.song.title, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall)
                Text(
                    current.song.artist,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(
                onClick = {
                    model.command(
                        JSONObject()
                            .put("kind", if (playing) "playback.pause" else "playback.resume")
                            .put("occurrence_id", current.occurrenceId),
                        if (playing) "playback.pause" else "playback.resume",
                    )
                },
                enabled = state.connected,
            ) {
                Icon(
                    cadenzaVector(if (playing) CadenzaIcon.PAUSE else CadenzaIcon.PLAY),
                    contentDescription = if (playing) "Pause" else "Play",
                )
            }
        }
    }
}
