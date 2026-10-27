package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.cadenza.remote.RemoteModel
import app.cadenza.remote.RemoteState
import org.json.JSONObject

@Composable
fun PlayingScreen(
    model: RemoteModel,
    state: RemoteState,
    wide: Boolean,
    restoreLyricsFocus: Boolean,
    onLyricsFocusRestored: () -> Unit,
    onOpenLyrics: () -> Unit,
) {
    val lyricsFocusRequester = remember { FocusRequester() }
    LaunchedEffect(restoreLyricsFocus) {
        if (restoreLyricsFocus) {
            repeat(2) { withFrameNanos { } }
            runCatching { lyricsFocusRequester.requestFocus() }
            onLyricsFocusRestored()
        }
    }
    val contentModifier =
        if (wide) {
            Modifier.fillMaxSize().padding(24.dp)
        } else {
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp)
        }
    Column(
        contentModifier,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        ScreenHeader("Now playing", state)
        FilterChip(
            selected = false,
            onClick = onOpenLyrics,
            label = { Text("Lyrics") },
            leadingIcon = { Icon(cadenzaVector(CadenzaIcon.LYRICS), contentDescription = null) },
            modifier = Modifier.focusRequester(lyricsFocusRequester),
        )
        val current = state.snapshot?.current
        if (current == null) {
            Text("Nothing is playing", style = MaterialTheme.typography.headlineSmall)
            Text("Search for a song and add it to Cadenza Host queue.")
            return@Column
        }
        if (wide) {
            Row(horizontalArrangement = Arrangement.spacedBy(32.dp), verticalAlignment = Alignment.CenterVertically) {
                Artwork(current.song.artworkUrl, Modifier.weight(1f).widthIn(max = 380.dp).aspectRatio(1f))
                PlayerDetails(model, state, Modifier.weight(1f))
            }
        } else {
            Artwork(current.song.artworkUrl, Modifier.widthIn(max = 300.dp).fillMaxWidth().aspectRatio(1f))
            PlayerDetails(model, state, Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun PlayerDetails(
    model: RemoteModel,
    state: RemoteState,
    modifier: Modifier,
) {
    val snapshot = state.snapshot ?: return
    val current = snapshot.current ?: return
    val owner = current.requestedBy == state.profile?.remoteId
    val canInterrupt = mayInterruptPlayback(state)
    val currentPosition = position(model)
    val observationsCurrent = !model.isStale()
    val mixing = snapshot.mixing.takeIf { observationsCurrent }
    var volume by remember { mutableFloatStateOf(-1f) }
    val volumeSlider = remember { SliderState(trackRange = 0f..100f) }
    volumeSlider.value = if (volume >= 0) volume else snapshot.volume.toFloat()
    Column(modifier, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(current.song.title, style = MaterialTheme.typography.headlineLarge)
        Text(current.song.artist, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        AssistChip(
            onClick = {
                model.showError(
                    "Request ownership",
                    if (canInterrupt) {
                        "You can control this request."
                    } else {
                        "This request belongs to " + current.requesterName +
                            ". Host settings protect it from skipping, seeking, and replacement. Pause and resume are shared."
                    },
                )
            },
            label = { Text("Requested by " + if (owner) "you" else current.requesterName) },
            leadingIcon =
                if (!canInterrupt) {
                    { Icon(cadenzaVector(CadenzaIcon.LOCK), contentDescription = "Protected request", modifier = Modifier.size(18.dp)) }
                } else {
                    null
                },
        )
        Text(
            when (if (observationsCurrent) snapshot.quality else "unknown") {
                "lossless" -> "Lossless"
                "hi_res_lossless" -> "Hi-Res Lossless"
                "dolby_atmos" -> "Dolby Atmos"
                "unknown" -> "Quality waiting for Cadenza Host"
                else -> "Quality not reported by Cadenza Host"
            },
            style = MaterialTheme.typography.bodyMedium,
        )
        if (mixing == true && snapshot.incoming != null) {
            Text("AutoMix → " + snapshot.incoming.title, style = MaterialTheme.typography.titleMedium)
        } else if (mixing == true) {
            Text("AutoMix transition �· Incoming song not reported", style = MaterialTheme.typography.bodyMedium)
        } else if (mixing == null) {
            Text(
                if (observationsCurrent) "AutoMix not reported by Cadenza Host" else "AutoMix status waiting for Cadenza Host",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        PlaybackTimeline(model, state, currentPosition)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            PlaybackTransport(model, state, Modifier.weight(1f))
            FavoriteIconButton(model, state, current.song)
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Music volume", style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f))
            Box(Modifier.size(24.dp)) {
                if ("playback.volume" in
                    state.pending
                ) {
                    CircularProgressIndicator(Modifier.size(24.dp).semantics { contentDescription = "Volume change pending" })
                }
            }
        }
        Slider(
            state = volumeSlider,
            onValueChange = { volume = it },
            modifier = Modifier.semantics { contentDescription = "Music volume" },
            onValueChangeFinished = {
                val target = volume.coerceAtLeast(0f).toInt()
                volume = -1f
                model.command(JSONObject().put("kind", "playback.volume").put("percent", target), "playback.volume")
            },
            enabled = state.connected && "playback.volume" !in state.pending,
        )
        ActionButton(if (state.monitoringSong) "Unpin song status" else "Pin song status", enabled = state.connected) {
            if (state.monitoringSong) model.endSessionStatus() else model.monitorSong()
        }
    }
}
