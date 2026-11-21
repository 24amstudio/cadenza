package app.cadenza.remote.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.BrowseTarget
import app.cadenza.remote.energy.LocalEnergyProfile
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.model.isStale
import app.cadenza.remote.model.playAutoPlay
import app.cadenza.remote.ui.browse.browseLink
import org.json.JSONObject

@Composable
fun PlayingScreen(
    model: RemoteModel,
    state: RemoteState,
    wide: Boolean,
    restoreLyricsFocus: Boolean,
    onLyricsFocusRestored: () -> Unit,
    onOpenLyrics: () -> Unit,
    // Null where the screen is a pane that has nothing to close to, such as the wide Home.
    onClose: (() -> Unit)? = null,
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
    // This screen draws only the timeline, which moves less than a pixel in 250 ms.
    val currentPosition = (position(model, LocalEnergyProfile.current.progressTickMs) + LYRIC_VISUAL_LEAD_MS).coerceAtLeast(0)
    // The song on screen trails the playing one until its artwork is ready, so a song change swaps both together.
    val shown = rememberShownSong(current)
    val backdrop = rememberBackdrop(shown?.artwork?.accent, 0.28f, MaterialTheme.colorScheme.surfaceContainerLow)
    val lyrics = state.lyrics?.takeIf { it.occurrenceId == current?.occurrenceId && it.level > 0 }
    val lyricsMayBeAvailable = current != null && (lyrics != null || (state.lyrics == null && state.lyricsIssue == null))
    var showQueue by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(current?.occurrenceId) {
        showQueue = false
    }
    LaunchedEffect(current?.occurrenceId, state.connected) {
        if (current != null && state.connected && lyrics == null && !state.lyricsLoading) {
            model.loadLyrics(userInitiated = false)
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(backdrop)) {
        // The wide Home shows this screen in its detail pane, which is narrower than the window, so the tablet layout starts
        // at a smaller width than a full-window screen would need.
        val tablet = wide && maxWidth >= 480.dp
        val contentPadding = if (wide) 28.dp else 20.dp
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding),
            verticalArrangement = Arrangement.spacedBy(if (wide) 20.dp else 16.dp),
        ) {
            PlayerHeader(
                state,
                lyricsMayBeAvailable,
                showQueue,
                compact = !tablet,
                lyricsFocusRequester = lyricsFocusRequester,
                onOpenLyrics = onOpenLyrics,
                onClose = onClose,
                onQueueChanged = { showQueue = it },
            )
            if (current == null || shown == null) {
                EmptyPlayerSurface()
            } else {
                if (tablet) {
                    Surface(
                        Modifier.fillMaxWidth(),
                        shape = MaterialTheme.shapes.extraLarge,
                        color = MaterialTheme.colorScheme.surfaceContainerLow.copy(alpha = 0.88f),
                        tonalElevation = 2.dp,
                    ) {
                        PlayerPanel(
                            model,
                            state,
                            shown,
                            currentPosition,
                            lyricsButton =
                                if (lyricsMayBeAvailable) {
                                    { LyricsButton(onOpenLyrics, Modifier.focusRequester(lyricsFocusRequester)) }
                                } else {
                                    null
                                },
                        )
                    }
                } else {
                    PortraitPlayerPanel(model, state, shown, currentPosition)
                }
                if (showQueue) QueuePreview(model, state)
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
    showQueue: Boolean,
    compact: Boolean,
    lyricsFocusRequester: FocusRequester,
    onOpenLyrics: () -> Unit,
    onClose: (() -> Unit)?,
    onQueueChanged: (Boolean) -> Unit,
) {
    if (compact) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                if (onClose != null) {
                    IconButton(onClick = onClose, modifier = Modifier.size(48.dp)) {
                        Icon(cadenzaVector(CadenzaIcon.DOWN), contentDescription = "Close now playing")
                    }
                } else {
                    Spacer(Modifier.size(48.dp))
                }
                Column(
                    Modifier.weight(1f),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text("Now playing", style = MaterialTheme.typography.titleLarge)
                    ConnectionStatus(state)
                }
                Spacer(Modifier.size(48.dp))
            }
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (lyricsMayBeAvailable) {
                    FilterChip(
                        selected = false,
                        onClick = onOpenLyrics,
                        label = { Text("Lyrics") },
                        leadingIcon = { Icon(cadenzaVector(CadenzaIcon.LYRICS), contentDescription = null) },
                        modifier = Modifier.focusRequester(lyricsFocusRequester),
                    )
                }
                FilterChip(
                    selected = showQueue,
                    onClick = { onQueueChanged(!showQueue) },
                    label = { Text("Up next") },
                    modifier = Modifier.semantics { contentDescription = "Queue view" },
                )
            }
        }
        return
    }
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (onClose != null) {
            IconButton(onClick = onClose, modifier = Modifier.size(48.dp)) {
                Icon(cadenzaVector(CadenzaIcon.DOWN), contentDescription = "Close now playing")
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(if (state.snapshot?.current == null) "Ready to play" else "Now playing", style = MaterialTheme.typography.headlineMedium)
            ConnectionStatus(state)
        }
        FilterChip(
            selected = showQueue,
            onClick = { onQueueChanged(!showQueue) },
            label = { Text("Up next") },
            modifier = Modifier.semantics { contentDescription = "Queue view" },
        )
    }
}

@Composable
private fun QueuePreview(
    model: RemoteModel,
    state: RemoteState,
) {
    val entries =
        state.snapshot
            ?.queue
            .orEmpty()
            .take(8)
    val autoPlay = state.snapshot?.autoPlay.orEmpty()
    Surface(
        Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Up next", style = MaterialTheme.typography.titleLarge)
            if (entries.isEmpty() && autoPlay.isEmpty()) {
                Text("Queue is empty", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            entries.forEachIndexed { index, entry ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("${index + 1}", color = MaterialTheme.colorScheme.primary)
                    Column(Modifier.weight(1f)) {
                        Text(entry.song.title, style = MaterialTheme.typography.titleMedium)
                        Text(entry.song.artist, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            // Music plays these once the queue is empty, so they are the next songs the Host will play.
            if (autoPlay.isNotEmpty()) {
                Text("AutoPlay", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                autoPlay.forEach { item ->
                    AutoPlayRow(item, state) { next -> model.playAutoPlay(item, next) }
                }
            }
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

// Cover, title and artist are one unit that crossfades when the song changes. Everything below it is controls.
// [modifier] sizes the cover; the title row always spans the width.
@Composable
private fun SongCover(
    model: RemoteModel,
    state: RemoteState,
    song: ShownSong,
    snapshotPlaying: Boolean,
    modifier: Modifier,
    titleStyle: TextStyle,
    titleMaxLines: Int,
    trailing: (@Composable () -> Unit)? = null,
) {
    val current = song.current
    val owner = current.requestedBy == state.profile?.remoteId
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        MotionArtwork(
            video = state.motion?.takeIf { it.occurrenceId == current.occurrenceId }?.file,
            playing = snapshotPlaying,
            modifier = Modifier.sharedArtwork(current.occurrenceId).then(modifier),
        ) {
            Artwork(song.artwork, Modifier.fillMaxSize())
        }
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(current.song.title, style = titleStyle, maxLines = titleMaxLines)
                Text(
                    current.song.artist,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.browseLink(state, current.song, "Open artist page") { BrowseTarget.artist(it) },
                )
                current.song.album.takeIf(String::isNotBlank)?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.browseLink(state, current.song, "Open album page") { BrowseTarget.album(it) },
                    )
                }
                if (current.requesterName.isNotBlank()) {
                    Text(
                        "Requested by " + if (owner) "you" else current.requesterName,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            LiveLinkIndicator(model, state, Modifier.padding(top = 6.dp))
            trailing?.invoke()
        }
    }
}

@Composable
private fun PortraitPlayerPanel(
    model: RemoteModel,
    state: RemoteState,
    shown: ShownSong,
    currentPosition: Long,
) {
    val snapshot = state.snapshot ?: return
    val current = snapshot.current ?: return
    val observationsCurrent = !model.isStale()
    val mixing = snapshot.mixing.takeIf { observationsCurrent }
    var volume by remember { mutableFloatStateOf(-1f) }
    val volumeSlider = remember { SliderState(trackRange = 0f..100f) }
    volumeSlider.value = if (volume >= 0) volume else snapshot.volume.toFloat()
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        SongSwap(shown, { it.current.occurrenceId }) { song ->
            SongCover(
                model,
                state,
                song,
                snapshot.playing,
                Modifier.widthIn(max = 420.dp).fillMaxWidth().aspectRatio(1f),
                MaterialTheme.typography.headlineSmall,
                titleMaxLines = 2,
                trailing = { FavoriteIconButton(model, state, song.current.song) },
            )
        }
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                qualityLabel(snapshot.quality, observationsCurrent),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                when (mixing) {
                    true -> "AutoMix"
                    false -> "AutoMix off"
                    null -> "AutoMix status waiting for Cadenza Host"
                },
                style = MaterialTheme.typography.labelMedium,
                color = if (mixing == true) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        PlaybackTimeline(model, state, currentPosition)
        PlaybackTransport(
            model,
            state,
            compact = false,
            leadingContent = shuffleSlot(model, state),
            trailingContent = repeatSlot(model, state),
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Music volume", style = MaterialTheme.typography.labelLarge)
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
        }
        SingControls(model, state, current)
    }
}

@Composable
private fun PlayerPanel(
    model: RemoteModel,
    state: RemoteState,
    shown: ShownSong,
    currentPosition: Long,
    lyricsButton: (@Composable () -> Unit)?,
) {
    val snapshot = state.snapshot ?: return
    val current = snapshot.current ?: return
    var volume by remember { mutableFloatStateOf(-1f) }
    val volumeSlider = remember { SliderState(trackRange = 0f..100f) }
    volumeSlider.value = if (volume >= 0) volume else snapshot.volume.toFloat()
    Column(
        Modifier.fillMaxWidth().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        SongSwap(shown, { it.current.occurrenceId }) { song ->
            SongCover(
                model,
                state,
                song,
                snapshot.playing,
                Modifier.widthIn(max = 300.dp).fillMaxWidth().aspectRatio(1f),
                MaterialTheme.typography.titleLarge,
                titleMaxLines = 2,
            )
        }
        HorizontalDivider()
        PlaybackTimeline(model, state, currentPosition)
        TabletTransport(model, state, lyricsButton)
        HorizontalDivider()
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

internal fun qualityLabel(
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
