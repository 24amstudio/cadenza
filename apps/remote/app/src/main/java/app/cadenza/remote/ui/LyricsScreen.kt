package app.cadenza.remote.ui

import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.CurrentPlayback
import app.cadenza.remote.data.LyricDocument
import app.cadenza.remote.energy.LocalEnergyProfile
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.model.isStale
import app.cadenza.remote.model.position
import app.cadenza.remote.ui.lyrics.FollowActiveLine
import app.cadenza.remote.ui.lyrics.LyricList
import app.cadenza.remote.ui.lyrics.LyricPlayback
import app.cadenza.remote.ui.lyrics.LyricsClock
import app.cadenza.remote.ui.lyrics.activeLineIndices
import app.cadenza.remote.ui.lyrics.rememberReducedMotion
import app.cadenza.remote.ui.lyrics.rememberSweeps
import app.cadenza.remote.ui.lyrics.rememberUserScrollConnection

internal fun activeLyricIndices(
    document: LyricDocument?,
    occurrence: String?,
    positionMs: Long,
    synchronized: Boolean,
): List<Int> {
    if (!synchronized || occurrence == null || document?.occurrenceId != occurrence) return emptyList()
    return activeLineIndices(document.lines, positionMs)
}

@Composable
fun LyricsScreen(
    model: RemoteModel,
    state: RemoteState,
    onExit: () -> Unit = {},
) {
    val current = state.snapshot?.current
    KeepScreenAwake(state.snapshot?.playing == true && current != null)
    val occurrence = current?.occurrenceId
    val stale = !state.connected || model.isStale()
    // A small lead compensates for the Host sample and Compose frame boundary so the
    // highlighted line changes when the performer hears the cue instead of after it.
    val currentPosition = (position(model, LocalEnergyProfile.current.lyricTickMs) + LYRIC_VISUAL_LEAD_MS).coerceAtLeast(0)
    // The song on screen trails the playing one until its artwork is ready, so a song change swaps both together.
    val shown = rememberShownSong(current)
    val shownOccurrence = shown?.current?.occurrenceId
    val document = rememberHeldLyrics(shownOccurrence, state.lyrics?.takeIf { it.occurrenceId == shownOccurrence })
    val backdrop =
        rememberBackdrop(
            accent = shown?.artwork?.accent,
            accentAlpha = 0.30f,
            fallbackTop = MaterialTheme.colorScheme.primaryContainer,
        )
    LaunchedEffect(occurrence, state.connected) {
        if (occurrence != null && state.connected && state.lyrics?.occurrenceId != occurrence && !state.lyricsLoading) {
            model.loadLyrics(userInitiated = false)
        }
    }
    BoxWithConstraints(
        Modifier.fillMaxSize().background(backdrop),
    ) {
        val expanded = maxWidth >= 720.dp
        val compactHeader = maxWidth < 400.dp && LocalDensity.current.fontScale >= 1.5f
        // Portrait gives the lyrics the most height: the header and the cover row stay small, and the lyric pane takes the rest.
        val gap = if (expanded) 12.dp else 8.dp
        Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(gap)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onExit) { Icon(cadenzaVector(CadenzaIcon.BACK), contentDescription = "Back to player") }
                if (compactHeader) {
                    Spacer(Modifier.weight(1f))
                } else {
                    Text("Now playing", Modifier.weight(1f), style = MaterialTheme.typography.headlineSmall, maxLines = 1)
                }
                FilterChip(
                    selected = true,
                    onClick = onExit,
                    label = { Text("Lyrics") },
                    leadingIcon = { Icon(cadenzaVector(CadenzaIcon.LYRICS), contentDescription = null) },
                )
            }
            val song = shown
            if (expanded && song != null && current != null) {
                Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                    Column(Modifier.weight(0.42f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SongSwap(song, { it.current.occurrenceId }) { entry ->
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                MotionArtwork(
                                    video = state.motion?.takeIf { it.occurrenceId == entry.current.occurrenceId }?.file,
                                    playing = state.snapshot.playing,
                                    modifier =
                                        Modifier
                                            .sharedArtwork(entry.current.occurrenceId)
                                            .widthIn(max = 260.dp)
                                            .fillMaxWidth()
                                            .aspectRatio(1f),
                                ) {
                                    Artwork(entry.artwork, Modifier.fillMaxSize())
                                }
                                TrackIdentity(entry.current, state.profile?.remoteId, quality = state.snapshot.quality)
                            }
                        }
                        Spacer(Modifier.weight(1f))
                        PlaybackTimeline(model, state, currentPosition)
                        LyricsTransport(model, state, current)
                        SingControls(model, state, current)
                    }
                    LyricsPane(model, state, document, shownOccurrence, currentPosition, stale, Modifier.weight(0.58f).fillMaxHeight())
                }
            } else {
                song?.let { entry ->
                    SongSwap(entry, { it.current.occurrenceId }) {
                        CompactTrackIdentity(it.current, state.profile?.remoteId, it.artwork, quality = state.snapshot?.quality)
                    }
                }
                LyricsPane(model, state, document, shownOccurrence, currentPosition, stale, Modifier.weight(1f).fillMaxWidth())
                if (current != null) {
                    PlaybackTimeline(model, state, currentPosition)
                    LyricsTransport(model, state, current, fillWidth = true)
                    SingControls(model, state, current)
                }
            }
        }
    }
}

// Previous, Play/Pause, Next and Favorite share the row evenly, so the group stays on screen at any width.
@Composable
private fun LyricsTransport(
    model: RemoteModel,
    state: RemoteState,
    current: CurrentPlayback,
    fillWidth: Boolean = false,
) {
    PlaybackTransport(
        model,
        state,
        compact = true,
        fillWidth = fillWidth,
        trailingContent = { FavoriteIconButton(model, state, current.song) },
    )
}

@Composable
private fun TrackIdentity(
    current: CurrentPlayback,
    remoteId: String?,
    quality: String? = null,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(current.song.title, style = MaterialTheme.typography.headlineSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(current.song.artist, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
        val requester = if (remoteId != null && current.requestedBy == remoteId) "you" else current.requesterName
        Text("Requested by $requester", style = MaterialTheme.typography.labelMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
        quality?.takeIf { it != "unknown" }?.let {
            Text(
                qualityLabel(it, current = true),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun CompactTrackIdentity(
    current: CurrentPlayback,
    remoteId: String?,
    artwork: ArtworkData?,
    quality: String? = null,
) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Artwork(artwork, Modifier.sharedArtwork(current.occurrenceId).size(48.dp))
        TrackIdentity(current, remoteId, quality = quality, modifier = Modifier.weight(1f))
    }
}

/** The lyrics of one song, held so the pane can finish fading out while the next song's lyrics load. */
@Immutable
private class LyricsFrame(
    val occurrence: String?,
    val document: LyricDocument?,
    val positionMs: Long,
)

/** Keeps [live] until the occurrence changes, since the model clears its lyrics as soon as the next song starts. */
@Composable
private fun rememberHeldLyrics(
    occurrence: String?,
    live: LyricDocument?,
): LyricDocument? {
    var held by remember(occurrence) { mutableStateOf(live) }
    LaunchedEffect(live) { if (live != null) held = live }
    return live ?: held
}

@Composable
private fun LyricsPane(
    model: RemoteModel,
    state: RemoteState,
    document: LyricDocument?,
    occurrence: String?,
    currentPosition: Long,
    stale: Boolean,
    modifier: Modifier = Modifier,
) {
    val frame = LyricsFrame(occurrence, document, currentPosition)
    val liveOccurrence = state.snapshot?.current?.occurrenceId
    SongSwap(frame, { it.occurrence.orEmpty() }, modifier) { entry ->
        LyricsContent(model, state, entry.document, entry.occurrence, entry.positionMs, stale, frozen = entry.occurrence != liveOccurrence)
    }
}

/**
 * The lyric lines of [occurrence]. A [frozen] pane belongs to a song that is no longer playing and only finishes its
 * exit: it keeps its position and runs no sweep.
 */
@Composable
internal fun LyricsContent(
    model: RemoteModel,
    state: RemoteState,
    document: LyricDocument?,
    occurrence: String?,
    currentPosition: Long,
    stale: Boolean,
    modifier: Modifier = Modifier,
    frozen: Boolean = false,
) {
    key(occurrence) {
        val list = rememberLazyListState()
        var following by rememberSaveable { mutableStateOf(true) }
        val reduced = rememberReducedMotion()
        // Translations already in the document reveal together when this song's lyrics first appear.
        // Later arrivals animate on their own, and lines that scroll into view afterward appear as-is.
        val translationReveal = remember { MutableTransitionState(false) }
        LaunchedEffect(document != null) { translationReveal.targetState = document != null }
        val active = activeLyricIndices(document, occurrence, currentPosition, !stale)
        // Follow the oldest sounding line: an overlapping background line starting later does not move the list.
        val anchor = active.minOrNull() ?: -1
        val userScroll = rememberUserScrollConnection { following = false }
        val energy = LocalEnergyProfile.current
        FollowActiveLine(list, anchor, document?.revision, following, reduced || energy.reduceTransitions)
        // The sweep reads a frame-sampled position while the song plays and this screen is started.
        val clock = remember(model) { LyricsClock { now -> (model.position(now) + LYRIC_VISUAL_LEAD_MS).coerceAtLeast(0) } }
        val sweep by rememberSweeps(
            lines = document?.lines.orEmpty(),
            clock = clock,
            enabled = document?.level == 3 && !stale && !reduced && !frozen,
            playing = state.snapshot?.playing == true,
            pausedPositionMs = currentPosition,
            frameCapFps = energy.lyricFrameCapFps,
        )
        Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (stale) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        cadenzaVector(CadenzaIcon.WIFI_OFF),
                        contentDescription = "Reconnecting to Host",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(20.dp),
                    )
                    Text("Synchronization paused.", style = MaterialTheme.typography.bodyMedium)
                }
            }
            when {
                document == null && state.lyricsLoading -> {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                        Text("Loading lyrics…")
                    }
                }
                document == null || document.lines.isEmpty() -> {
                    Text(
                        state.lyricsIssue ?: document?.issue ?: if (occurrence == null) {
                            "Play a song to see its lyrics."
                        } else {
                            "Lyrics are unavailable. Open the lyrics pane in Cadenza Host and retry."
                        },
                    )
                    ActionButton("Retry lyrics", pending = state.lyricsLoading, enabled = state.connected && occurrence != null) {
                        model.loadLyrics()
                    }
                }
                else -> {
                    lyricsSourceLabel(document)?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    document.issue?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium)
                        ActionButton("Reload lyrics", pending = state.lyricsLoading, enabled = state.connected) { model.loadLyrics() }
                    }
                    if (!following) {
                        TextButton(onClick = { following = true }) { Text("Follow current line") }
                    }
                    LyricList(
                        document = document,
                        playback = LyricPlayback(currentPosition, active, sweep, !stale, clock),
                        list = list,
                        userScroll = userScroll,
                        reduced = reduced,
                        translationRevealed = translationReveal.targetState,
                        textSize = state.lyricsTextSize,
                        canSeek = { index ->
                            val line = document.lines[index]
                            state.connected && !stale && mayInterruptPlayback(state) && line.endMs > line.startMs
                        },
                        onSeek = { positionMs ->
                            model.command(
                                org.json
                                    .JSONObject()
                                    .put("kind", "playback.seek")
                                    .put("occurrence_id", occurrence)
                                    .put("position_ms", positionMs),
                                "playback.seek",
                            )
                        },
                        modifier = Modifier.weight(1f).fillMaxWidth(),
                    )
                }
            }
        }
    }
}

// The Host sample and the next Compose frame arrive after the audible cue on real devices.
// Keep word emphasis ahead of that boundary so it does not visibly trail the singer.
internal const val LYRIC_VISUAL_LEAD_MS = 280L

/** Lyrics from the music provider need no label. Only the fallback provider is named. */
internal fun lyricsSourceLabel(document: LyricDocument): String? = if (document.source == "lrclib") "Lyrics from LRCLIB" else null
