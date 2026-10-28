package app.cadenza.remote.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderState
import androidx.compose.material3.Surface
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.cadenza.remote.RemoteModel
import app.cadenza.remote.RemoteState
import app.cadenza.remote.showError
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
    KeepScreenAwake(state.snapshot?.playing == true && state.snapshot.current != null)
    val lyricsFocusRequester = remember { FocusRequester() }
    LaunchedEffect(restoreLyricsFocus) {
        if (restoreLyricsFocus) {
            repeat(2) { withFrameNanos { } }
            runCatching { lyricsFocusRequester.requestFocus() }
            onLyricsFocusRestored()
        }
    }
    val current = state.snapshot?.current
    val artwork = rememberArtwork(current?.song?.artworkUrl)
    val backdrop =
        artwork?.accent?.let {
            Brush.verticalGradient(
                listOf(it.copy(alpha = 0.24f), MaterialTheme.colorScheme.surface.copy(alpha = 0.96f), MaterialTheme.colorScheme.surface),
            )
        } ?: Brush.verticalGradient(listOf(MaterialTheme.colorScheme.surfaceContainerLow, MaterialTheme.colorScheme.surface))
    val lyrics = state.lyrics?.takeIf { it.occurrenceId == current?.occurrenceId && it.level > 0 }
    val lyricsMayBeAvailable = current != null && (lyrics != null || (state.lyrics == null && state.lyricsIssue == null))

    Box(Modifier.fillMaxSize().background(backdrop)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(if (current == null) "Ready to play" else "Now playing", style = MaterialTheme.typography.headlineMedium)
                    ConnectionStatus(state)
                }
                if (!wide && lyricsMayBeAvailable) {
                    FilterChip(
                        selected = false,
                        onClick = onOpenLyrics,
                        label = { Text("Lyrics") },
                        leadingIcon = { Icon(cadenzaVector(CadenzaIcon.LYRICS), contentDescription = null) },
                        modifier = Modifier.focusRequester(lyricsFocusRequester),
                    )
                }
            }
            if (current == null) {
                Surface(
                    Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.extraLarge,
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    tonalElevation = 2.dp,
                ) {
                    Row(
                        Modifier.padding(24.dp),
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Surface(
                            Modifier.size(64.dp),
                            shape = MaterialTheme.shapes.large,
                            color = MaterialTheme.colorScheme.primaryContainer,
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    cadenzaVector(CadenzaIcon.MUSIC),
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                                    modifier = Modifier.size(32.dp),
                                )
                            }
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("Nothing is playing", style = MaterialTheme.typography.titleLarge)
                            Text(
                                "Search for a song and add it to the Host queue.",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            } else {
                Surface(
                    Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.extraLarge,
                    color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.22f),
                    tonalElevation = 3.dp,
                ) {
                    if (wide) {
                        Column(
                            Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 18.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Artwork(artwork, Modifier.size(170.dp))
                            PlayerDetails(
                                model,
                                state,
                                Modifier.fillMaxWidth(),
                                true,
                                lyricsMayBeAvailable,
                                onOpenLyrics,
                                lyricsFocusRequester,
                            )
                        }
                    } else {
                        Column(
                            Modifier.fillMaxWidth().padding(20.dp),
                            verticalArrangement = Arrangement.spacedBy(20.dp),
                        ) {
                            Artwork(
                                artwork,
                                Modifier
                                    .widthIn(max = 320.dp)
                                    .fillMaxWidth()
                                    .aspectRatio(1f)
                                    .align(Alignment.CenterHorizontally),
                            )
                            PlayerDetails(
                                model,
                                state,
                                Modifier.fillMaxWidth(),
                                false,
                                lyricsMayBeAvailable,
                                onOpenLyrics,
                                lyricsFocusRequester,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PlayerDetails(
    model: RemoteModel,
    state: RemoteState,
    modifier: Modifier,
    wide: Boolean,
    lyricsMayBeAvailable: Boolean,
    onOpenLyrics: () -> Unit,
    lyricsFocusRequester: FocusRequester,
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
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(current.song.title, style = MaterialTheme.typography.headlineSmall)
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
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
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
            if (mixing == true) {
                Text("• AutoMix", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            }
        }
        if (mixing == true && snapshot.incoming != null) {
            Text("AutoMix → " + snapshot.incoming.title, style = MaterialTheme.typography.bodyMedium)
        } else if (mixing == true) {
            Text("AutoMix transition - Incoming song not reported", style = MaterialTheme.typography.bodyMedium)
        } else if (mixing == null) {
            Text(
                if (observationsCurrent) "AutoMix not reported by Cadenza Host" else "AutoMix status waiting for Cadenza Host",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        HorizontalDivider()
        PlaybackTimeline(model, state, currentPosition)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            PlaybackTransport(
                model,
                state,
                Modifier.weight(1f),
                leadingContent =
                    if (wide && lyricsMayBeAvailable) {
                        {
                            FilterChip(
                                selected = false,
                                onClick = onOpenLyrics,
                                label = { Text("Lyrics") },
                                leadingIcon = { Icon(cadenzaVector(CadenzaIcon.LYRICS), contentDescription = null) },
                                modifier = Modifier.focusRequester(lyricsFocusRequester),
                            )
                        }
                    } else {
                        null
                    },
            )
            FavoriteIconButton(model, state, current.song)
        }
        HorizontalDivider()
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Music volume", style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f))
            Box(Modifier.size(24.dp)) {
                if ("playback.volume" in state.pending) {
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
        OutlinedButton(
            onClick = { if (state.monitoringSong) model.endSessionStatus() else model.monitorSong() },
            enabled = state.connected,
            modifier = Modifier.fillMaxWidth(),
        ) { Text(if (state.monitoringSong) "Unpin song status" else "Pin song status") }
    }
}
