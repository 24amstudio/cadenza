package app.cadenza.remote.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.CurrentPlayback
import app.cadenza.remote.data.LyricDocument
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
import app.cadenza.remote.ui.lyrics.rememberSweepTarget
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
    val document = state.lyrics?.takeIf { it.occurrenceId == occurrence }
    val stale = !state.connected || model.isStale()
    // A small lead compensates for the Host sample and Compose frame boundary so the
    // highlighted line changes when the performer hears the cue instead of after it.
    val currentPosition = (position(model, 100) + LYRIC_VISUAL_LEAD_MS).coerceAtLeast(0)
    val artwork = rememberArtwork(current?.song?.artworkUrl)
    val backdrop =
        artwork?.accent?.let {
            Brush.verticalGradient(
                listOf(
                    it.copy(alpha = 0.30f),
                    MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
                    MaterialTheme.colorScheme.surface,
                ),
            )
        } ?: Brush.verticalGradient(listOf(MaterialTheme.colorScheme.primaryContainer, MaterialTheme.colorScheme.surface))
    LaunchedEffect(occurrence, state.connected) {
        if (occurrence != null && state.connected && document == null && !state.lyricsLoading) {
            model.loadLyrics(userInitiated = false)
        }
    }
    BoxWithConstraints(
        Modifier.fillMaxSize().background(backdrop),
    ) {
        val expanded = maxWidth >= 720.dp
        val compactHeader = maxWidth < 400.dp && LocalDensity.current.fontScale >= 1.5f
        Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
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
            if (expanded && current != null) {
                Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                    Column(Modifier.weight(0.42f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Artwork(artwork, Modifier.widthIn(max = 260.dp).fillMaxWidth().aspectRatio(1f))
                        TrackIdentity(current, state.profile?.remoteId)
                        Spacer(Modifier.weight(1f))
                        PlaybackTimeline(model, state, currentPosition)
                        PlaybackTransport(model, state, compact = true)
                        SingControls(model, state, current)
                    }
                    LyricsContent(model, state, document, currentPosition, stale, Modifier.weight(0.58f).fillMaxHeight())
                }
            } else {
                current?.let { CompactTrackIdentity(it, state.profile?.remoteId, artwork) }
                LyricsContent(model, state, document, currentPosition, stale, Modifier.weight(1f).fillMaxWidth())
                if (current != null) {
                    PlaybackTimeline(model, state, currentPosition)
                    PlaybackTransport(model, state, compact = true)
                    SingControls(model, state, current)
                }
            }
        }
    }
}

@Composable
private fun TrackIdentity(
    current: CurrentPlayback,
    remoteId: String?,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(current.song.title, style = MaterialTheme.typography.headlineSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(current.song.artist, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
        val requester = if (remoteId != null && current.requestedBy == remoteId) "you" else current.requesterName
        Text("Requested by $requester", style = MaterialTheme.typography.labelMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun CompactTrackIdentity(
    current: CurrentPlayback,
    remoteId: String?,
    artwork: ArtworkData?,
) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Artwork(artwork, Modifier.size(56.dp))
        TrackIdentity(current, remoteId, Modifier.weight(1f))
    }
}

@Composable
internal fun LyricsContent(
    model: RemoteModel,
    state: RemoteState,
    document: LyricDocument?,
    currentPosition: Long,
    stale: Boolean,
    modifier: Modifier = Modifier,
) {
    val occurrence = state.snapshot?.current?.occurrenceId
    key(occurrence) {
        val list = rememberLazyListState()
        var following by rememberSaveable { mutableStateOf(true) }
        val reduced = rememberReducedMotion()
        // Translations already in the document reveal together when this song's lyrics first appear.
        // Later arrivals animate on their own, and lines that scroll into view afterward appear as-is.
        val translationReveal = remember { MutableTransitionState(false) }
        LaunchedEffect(document != null) { translationReveal.targetState = document != null }
        val active = activeLyricIndices(document, occurrence, currentPosition, !stale)
        // Follow the newest sounding line; an overlapping background line stays visible just above it.
        val anchor = active.maxOrNull() ?: -1
        val userScroll = rememberUserScrollConnection { following = false }
        FollowActiveLine(list, anchor, document?.revision, following, reduced)
        // The sweep reads a frame-sampled position while the song plays and this screen is started.
        val clock = remember(model) { LyricsClock { now -> (model.position(now) + LYRIC_VISUAL_LEAD_MS).coerceAtLeast(0) } }
        val sweep by rememberSweepTarget(
            lines = document?.lines.orEmpty(),
            clock = clock,
            enabled = document?.level == 3 && !stale && !reduced,
            playing = state.snapshot?.playing == true,
            pausedPositionMs = currentPosition,
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
                    LyricsSource(document)
                    when (document.level) {
                        1 -> Text("Lyrics without timing", style = MaterialTheme.typography.bodyMedium)
                        2 -> Text("Timed by line", style = MaterialTheme.typography.bodyMedium)
                        3 -> Text("Timed by line and word", style = MaterialTheme.typography.bodyMedium)
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

@Composable
private fun LyricsSource(document: LyricDocument) {
    val source =
        when (document.source) {
            "lrclib" -> "LRCLIB"
            "apple_music" -> "Apple Music"
            else -> "Host provider"
        }
    val label =
        "$source · " +
            when (document.translationSource) {
                "apple" -> "English translation from Apple Music"
                "machine" -> "English machine translation"
                "apple_and_machine" -> "English translation from Apple Music and on-device translation"
                "original" -> "Original lyrics"
                else -> "Lyrics"
            }
    AnimatedContent(
        targetState = label,
        transitionSpec = { fadeIn(tween(320)) togetherWith fadeOut(tween(160)) },
        label = "lyrics-source",
    ) { text ->
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
