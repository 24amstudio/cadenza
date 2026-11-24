package app.cadenza.remote.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.AudioOutput
import app.cadenza.remote.data.Song
import app.cadenza.remote.model.RemoteModel
import org.json.JSONArray
import org.json.JSONObject

/** Chooses the Mac's audio output. Music plays to the default output, so the choice routes Music's audio there. */
@Composable
internal fun AudioOutputChooser(
    model: RemoteModel,
    outputs: List<AudioOutput>,
    enabled: Boolean,
    modifier: Modifier = Modifier,
) {
    if (outputs.isEmpty()) return

    Column(modifier) {
        Text("Audio output", style = MaterialTheme.typography.labelLarge)
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            outputs.forEach { output ->
                FilterChip(
                    selected = output.isDefault,
                    onClick = {
                        model.command(
                            JSONObject().put("kind", "audio.selectOutput").put("output", output.id),
                            "audio.selectOutput",
                        )
                    },
                    label = { Text(output.name) },
                    enabled = enabled,
                )
            }
        }
    }
}

/** Favorite the playing song in Music, or add it to the Cadenza Host playlist. Only library songs can be changed. */
@Composable
internal fun LibraryActions(
    model: RemoteModel,
    song: Song,
    enabled: Boolean,
    modifier: Modifier = Modifier,
) {
    if (song.source != "library") return

    val identity = JSONObject().put("source", "library").put("id", song.id)
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        FilterChip(
            selected = false,
            enabled = enabled,
            onClick = {
                model.command(
                    JSONObject().put("kind", "library.favorite").put("song", identity).put("enabled", true),
                    "library.favorite",
                )
            },
            label = { Text("Favorite in Music") },
        )
        FilterChip(
            selected = false,
            enabled = enabled,
            onClick = {
                model.command(
                    JSONObject()
                        .put("kind", "library.addToPlaylist")
                        .put("name", "Cadenza Host")
                        .put("songs", JSONArray().put(identity)),
                    "library.addToPlaylist",
                )
            },
            label = { Text("Add to Host playlist") },
        )
    }
}
