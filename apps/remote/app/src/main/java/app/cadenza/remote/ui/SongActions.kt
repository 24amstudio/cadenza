package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.Song
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import org.json.JSONObject

@Composable
fun FavoriteButton(
    model: RemoteModel,
    state: RemoteState,
    song: Song,
) {
    val saved = state.favorites.any { it.identity == song.identity }
    ActionButton(
        if (saved) "Remove from Favorites" else "Save to Favorites",
        pending = state.savingFavorite,
        enabled = song.source != "unknown",
    ) {
        model.toggleFavorite(song)
    }
}

@Composable
fun FavoriteIconButton(
    model: RemoteModel,
    state: RemoteState,
    song: Song,
) {
    val saved = state.favorites.any { it.identity == song.identity }
    IconButton(
        onClick = { model.toggleFavorite(song) },
        enabled = song.source != "unknown" && !state.savingFavorite,
        modifier = Modifier.sizeIn(minWidth = 56.dp, minHeight = 56.dp),
    ) {
        if (state.savingFavorite) {
            CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
        } else {
            Icon(
                cadenzaVector(CadenzaIcon.STAR),
                contentDescription = if (saved) "Remove from Favorites" else "Save to Favorites",
                tint = if (saved) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
fun SongActions(
    model: RemoteModel,
    state: RemoteState,
    song: Song,
    modifier: Modifier = Modifier,
) {
    val key = "enqueue:" + song.source + ":" + song.id
    val prepared = state.preparedSong == song.source + ":" + song.id
    val canQueue = state.connected && state.snapshot?.synchronized == true && prepared && !state.preparing
    val current = state.snapshot?.current
    val mayInterrupt =
        current == null || current.requestedBy == state.profile?.remoteId ||
            (state.snapshot.allowCrossRemoteEdits && current.requestedBy != null)

    BoxWithConstraints(modifier.fillMaxWidth()) {
        val spacious = maxWidth >= 500.dp
        val availableWidth = maxWidth
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(if (spacious) 28.dp else 20.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            SongIdentityCard(song, spacious, availableWidth)
            Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
                Column(
                    Modifier.fillMaxWidth().padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        ActionButton(
                            "Add to queue",
                            pending = state.preparing || key in state.pending,
                            enabled = canQueue,
                            modifier = Modifier.weight(1f),
                        ) {
                            model.command(JSONObject().put("kind", "queue.enqueue").put("song", song.identity.json()), key)
                        }
                        OutlinedButton(
                            onClick = { model.command(JSONObject().put("kind", "queue.play_next").put("song", song.identity.json()), key) },
                            enabled = canQueue && !state.preparing && "queue.play-next" in state.capabilities && key !in state.pending,
                            modifier = Modifier.weight(1f).sizeIn(minHeight = 56.dp),
                        ) { Text("Play next", maxLines = 1, overflow = TextOverflow.Ellipsis) }
                        FavoriteIconButton(model, state, song)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        FilledTonalButton(
                            onClick = {
                                model.command(
                                    JSONObject().put("kind", "queue.play_now").put("song", song.identity.json()).put(
                                        "occurrence_id",
                                        current?.occurrenceId ?: JSONObject.NULL,
                                    ),
                                    key,
                                )
                            },
                            enabled = canQueue && !state.preparing && mayInterrupt && key !in state.pending,
                            modifier = Modifier.weight(1f).sizeIn(minHeight = 56.dp),
                        ) { Text("Play now", maxLines = 1, overflow = TextOverflow.Ellipsis) }
                        if (!prepared) {
                            OutlinedButton(
                                onClick = { model.prepare(song) },
                                enabled = state.connected && !state.preparing,
                                modifier = Modifier.weight(1f).sizeIn(minHeight = 56.dp),
                            ) { Text("Prepare in Music", maxLines = 1, overflow = TextOverflow.Ellipsis) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SongIdentityCard(
    song: Song,
    spacious: Boolean,
    availableWidth: androidx.compose.ui.unit.Dp,
) {
    if (spacious) {
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Row(
                Modifier.fillMaxWidth().padding(18.dp),
                horizontalArrangement = Arrangement.spacedBy(20.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Artwork(song.artworkUrl, Modifier.size((availableWidth * 0.38f).coerceIn(160.dp, 220.dp)).aspectRatio(1f))
                SongMetadata(song, Modifier.weight(1f), centered = false)
            }
        }
    } else {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Artwork(song.artworkUrl, Modifier.widthIn(max = 248.dp).fillMaxWidth().aspectRatio(1f))
            SongMetadata(song, Modifier.fillMaxWidth(), centered = true)
        }
    }
}

@Composable
private fun SongMetadata(
    song: Song,
    modifier: Modifier,
    centered: Boolean,
) {
    Column(
        modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalAlignment = if (centered) Alignment.CenterHorizontally else Alignment.Start,
    ) {
        Text(
            song.title,
            style = MaterialTheme.typography.headlineMedium,
            textAlign = if (centered) TextAlign.Center else TextAlign.Start,
        )
        Text(
            song.artist,
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = if (centered) TextAlign.Center else TextAlign.Start,
        )
        listOf(song.album.takeIf(String::isNotBlank), song.durationMs?.let(::duration))
            .filterNotNull()
            .joinToString(" · ")
            .takeIf(String::isNotBlank)
            ?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = if (centered) TextAlign.Center else TextAlign.Start,
                )
            }
    }
}
