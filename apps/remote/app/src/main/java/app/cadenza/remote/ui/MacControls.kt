package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.Song
import app.cadenza.remote.model.RemoteModel
import org.json.JSONArray
import org.json.JSONObject

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
