package app.cadenza.remote.ui

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.cadenza.remote.RemoteModel
import app.cadenza.remote.RemoteState
import app.cadenza.remote.data.CurrentPlayback
import app.cadenza.remote.data.LyricDocument

internal fun activeLyricIndex(
    document: LyricDocument?,
    occurrence: String?,
    positionMs: Long,
    synchronized: Boolean,
): Int {
    if (!synchronized || occurrence == null || document?.occurrenceId != occurrence) return -1
    return document.lines.indexOfLast { it.endMs > it.startMs && it.startMs <= positionMs && positionMs < it.endMs }
}

@Composable
fun LyricsScreen(
    model: RemoteModel,
    state: RemoteState,
    onExit: () -> Unit = {},
) {
    val current = state.snapshot?.current
    val occurrence = current?.occurrenceId
    val document = state.lyrics?.takeIf { it.occurrenceId == occurrence }
    val stale = !state.connected || model.isStale()
    val currentPosition = position(model, 100)
    LaunchedEffect(occurrence, state.connected) {
        if (occurrence != null && state.connected && document == null && !state.lyricsLoading) {
            model.loadLyrics(userInitiated = false)
        }
    }
    BoxWithConstraints(
        Modifier.fillMaxSize().background(
            Brush.verticalGradient(
                listOf(MaterialTheme.colorScheme.primaryContainer, MaterialTheme.colorScheme.surface),
            ),
        ),
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
                        Artwork(current.song.artworkUrl, Modifier.widthIn(max = 260.dp).fillMaxWidth().aspectRatio(1f))
                        TrackIdentity(current, state.profile?.remoteId)
                        Spacer(Modifier.weight(1f))
                        PlaybackTimeline(model, state, currentPosition)
                        PlaybackTransport(model, state, compact = true)
                    }
                    LyricsContent(model, state, document, currentPosition, stale, Modifier.weight(0.58f).fillMaxHeight())
                }
            } else {
                current?.let { CompactTrackIdentity(it, state.profile?.remoteId) }
                LyricsContent(model, state, document, currentPosition, stale, Modifier.weight(1f).fillMaxWidth())
                if (current != null) {
                    PlaybackTimeline(model, state, currentPosition)
                    PlaybackTransport(model, state, compact = true)
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
) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Artwork(current.song.artworkUrl, Modifier.size(56.dp))
        TrackIdentity(current, remoteId, Modifier.weight(1f))
    }
}

@Composable
private fun LyricsContent(
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
        val active = activeLyricIndex(document, occurrence, currentPosition, !stale)
        val userScroll =
            remember {
                object : NestedScrollConnection {
                    override fun onPreScroll(
                        available: Offset,
                        source: NestedScrollSource,
                    ): Offset {
                        if (source == NestedScrollSource.UserInput && available.y != 0f) following = false
                        return Offset.Zero
                    }
                }
            }
        LaunchedEffect(active, document?.revision, following) {
            if (following && active >= 0) list.animateScrollToItem((active - 1).coerceAtLeast(0))
        }
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
                            "Lyrics are unavailable. Open Music’s lyrics pane on the Mac and retry."
                        },
                    )
                    ActionButton("Retry lyrics", pending = state.lyricsLoading, enabled = state.connected && occurrence != null) {
                        model.loadLyrics()
                    }
                }
                else -> {
                    LyricsSource(document)
                    if (document.lines.none { it.endMs > it.startMs }) {
                        Text("Timing unavailable", style = MaterialTheme.typography.bodyMedium)
                    }
                    document.issue?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium)
                        ActionButton("Reload lyrics", pending = state.lyricsLoading, enabled = state.connected) { model.loadLyrics() }
                    }
                    if (!following) {
                        TextButton(onClick = { following = true }) { Text("Follow current line") }
                    }
                    LazyColumn(
                        modifier = Modifier.weight(1f).fillMaxWidth().nestedScroll(userScroll),
                        state = list,
                        verticalArrangement = Arrangement.spacedBy(24.dp),
                    ) {
                        itemsIndexed(document.lines, key = { _, line -> line.id }) { index, line ->
                            Column(
                                Modifier.fillMaxWidth().padding(vertical = 6.dp).semantics(mergeDescendants = true) {
                                    selected = index == active
                                },
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    line.text,
                                    style = MaterialTheme.typography.headlineMedium,
                                    fontWeight = if (index == active) FontWeight.Bold else FontWeight.Normal,
                                    color = if (index == active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                                )
                                line.translation?.let {
                                    Text(
                                        it,
                                        style = MaterialTheme.typography.titleMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LyricsSource(document: LyricDocument) {
    Text(
        when (document.translationSource) {
            "apple" -> "English translation from Apple Music"
            "machine" -> "English machine translation"
            "apple_and_machine" -> "English translation from Apple Music and on-device translation"
            else -> "Original lyrics"
        },
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}
