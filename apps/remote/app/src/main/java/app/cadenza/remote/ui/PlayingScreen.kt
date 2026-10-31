package app.cadenza.remote.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.model.isStale
import app.cadenza.remote.model.showError
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
    val currentPosition = position(model, 100)
    val artwork = rememberArtwork(current?.song?.artworkUrl)
    val backdrop =
        artwork?.accent?.let {
            Brush.verticalGradient(
                listOf(it.copy(alpha = 0.28f), MaterialTheme.colorScheme.surface.copy(alpha = 0.96f), MaterialTheme.colorScheme.surface),
            )
        } ?: Brush.verticalGradient(listOf(MaterialTheme.colorScheme.surfaceContainerLow, MaterialTheme.colorScheme.surface))
    val lyrics = state.lyrics?.takeIf { it.occurrenceId == current?.occurrenceId && it.level > 0 }
    val lyricsMayBeAvailable = current != null && (lyrics != null || (state.lyrics == null && state.lyricsIssue == null))
    LaunchedEffect(current?.occurrenceId, state.connected) {
        if (current != null && state.connected && lyrics == null && !state.lyricsLoading) {
            model.loadLyrics(userInitiated = false)
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(backdrop)) {
        val tablet = wide && maxWidth >= 760.dp
        val contentPadding = if (wide) 28.dp else 20.dp
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding),
            verticalArrangement = Arrangement.spacedBy(if (wide) 20.dp else 16.dp),
        ) {
            PlayerHeader(state, lyricsMayBeAvailable, onOpenLyrics, lyricsFocusRequester)
            if (current == null) {
                EmptyPlayerSurface()
            } else if (tablet) {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 520.dp, max = 640.dp),
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    Surface(
                        Modifier.weight(0.44f),
                        shape = MaterialTheme.shapes.extraLarge,
                        color = MaterialTheme.colorScheme.surfaceContainerLow.copy(alpha = 0.86f),
                        tonalElevation = 2.dp,
                    ) {
                        PlayerPanel(model, state, artwork, currentPosition, true)
                    }
                    Surface(
                        Modifier.weight(0.56f).fillMaxSize(),
                        shape = MaterialTheme.shapes.extraLarge,
                        color = MaterialTheme.colorScheme.surfaceContainerLow.copy(alpha = 0.54f),
                        tonalElevation = 1.dp,
                    ) {
                        LyricsContent(
                            model,
                            state,
                            lyrics,
                            currentPosition,
                            !state.connected || model.isStale(),
                            Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 20.dp),
                        )
                    }
                }
            } else {
                Surface(
                    Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.extraLarge,
                    color = MaterialTheme.colorScheme.surfaceContainerLow.copy(alpha = 0.88f),
                    tonalElevation = 2.dp,
                ) {
                    PlayerPanel(model, state, artwork, currentPosition, false)
                }
                state.nextRecommendation?.let { recommendation ->
                    Surface(
                        Modifier.fillMaxWidth(),
                        shape = MaterialTheme.shapes.large,
                        color = MaterialTheme.colorScheme.surfaceContainerHigh,
                        tonalElevation = 1.dp,
                    ) {
                        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text("Up next", style = MaterialTheme.typography.titleMedium)
                            Text(
                                recommendation.title ?: recommendation.songId,
                                style = MaterialTheme.typography.bodyLarge,
                                modifier = Modifier.semantics { contentDescription = "CREE selected next song" },
                            )
                            recommendation.artist?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            recommendation.evidence.firstOrNull()?.let {
                                Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PlayerHeader(
    state: RemoteState,
    lyricsMayBeAvailable: Boolean,
    onOpenLyrics: () -> Unit,
    lyricsFocusRequester: FocusRequester,
) {
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(if (state.snapshot?.current == null) "Ready to play" else "Now playing", style = MaterialTheme.typography.headlineMedium)
            ConnectionStatus(state)
        }
        if (lyricsMayBeAvailable) {
            FilterChip(
                selected = false,
                onClick = onOpenLyrics,
                label = { Text("Lyrics") },
                leadingIcon = { Icon(cadenzaVector(CadenzaIcon.LYRICS), contentDescription = null) },
                modifier = Modifier.focusRequester(lyricsFocusRequester),
            )
        }
    }
}

@Composable
private fun EmptyPlayerSurface() {
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
                Text("Search for a song and add it to the Host queue.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun PlayerPanel(
    model: RemoteModel,
    state: RemoteState,
    artwork: ArtworkData?,
    currentPosition: Long,
    wide: Boolean,
) {
    val snapshot = state.snapshot ?: return
    val current = snapshot.current ?: return
    val owner = current.requestedBy == state.profile?.remoteId
    val canInterrupt = mayInterruptPlayback(state)
    val observationsCurrent = !model.isStale()
    val mixing = snapshot.mixing.takeIf { observationsCurrent }
    var volume by remember { mutableFloatStateOf(-1f) }
    val volumeSlider = remember { SliderState(trackRange = 0f..100f) }
    volumeSlider.value = if (volume >= 0) volume else snapshot.volume.toFloat()
    Column(
        Modifier.fillMaxWidth().padding(if (wide) 24.dp else 20.dp),
        verticalArrangement = Arrangement.spacedBy(if (wide) 14.dp else 16.dp),
        horizontalAlignment = if (wide) Alignment.CenterHorizontally else Alignment.Start,
    ) {
        val coverModifier =
            Modifier
                .widthIn(max = if (wide) 300.dp else 280.dp)
                .fillMaxWidth()
                .aspectRatio(1f)
                .align(Alignment.CenterHorizontally)
        MotionArtwork(
            video = state.motion?.takeIf { it.occurrenceId == current.occurrenceId }?.file,
            playing = snapshot.playing,
            modifier = coverModifier,
        ) {
            Artwork(artwork, Modifier.fillMaxSize())
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(current.song.title, style = if (wide) MaterialTheme.typography.titleLarge else MaterialTheme.typography.headlineSmall)
                Text(current.song.artist, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    "Requested by " + if (owner) "you" else current.requesterName,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            FavoriteIconButton(model, state, current.song)
        }
        if (!wide) {
            AssistChip(
                onClick = {
                    model.showError(
                        "Request ownership",
                        if (canInterrupt) {
                            "You can control this request."
                        } else {
                            "This request belongs to " + current.requesterName +
                                ". Pause and resume are shared."
                        },
                    )
                },
                label = { Text(if (owner) "Your request" else "Shared request") },
                leadingIcon =
                    if (!canInterrupt) {
                        { Icon(cadenzaVector(CadenzaIcon.LOCK), contentDescription = "Protected request", modifier = Modifier.size(18.dp)) }
                    } else {
                        null
                    },
            )
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(qualityLabel(snapshot.quality, observationsCurrent), style = MaterialTheme.typography.bodyMedium)
                if (mixing ==
                    true
                ) {
                    Text("· AutoMix", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                }
            }
            if (mixing == true && snapshot.incoming != null) {
                Text(
                    "AutoMix → " + snapshot.incoming.title,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else if (mixing == null) {
                Text(
                    if (observationsCurrent) "AutoMix not reported by Cadenza Host" else "AutoMix status waiting for Cadenza Host",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        HorizontalDivider()
        PlaybackTimeline(model, state, currentPosition)
        PlaybackTransport(model, state, Modifier.fillMaxWidth(), compact = true)
        HorizontalDivider()
        if (!wide) {
            Text("Music volume", style = MaterialTheme.typography.labelLarge)
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
            enabled = state.connected,
        )
        SingControls(model, state, current)
    }
}

private fun qualityLabel(
    quality: String,
    current: Boolean,
): String =
    when {
        !current -> "Quality waiting for Cadenza Host"
        quality == "lossless" -> "Lossless"
        quality == "hi_res_lossless" -> "Hi-Res Lossless"
        quality == "dolby_atmos" -> "Dolby Atmos"
        quality == "unknown" -> "Quality waiting for Cadenza Host"
        else -> "Quality not reported by Cadenza Host"
    }
