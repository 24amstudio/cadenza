package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState

@Composable
internal fun HomePlaybackPanel(
    model: RemoteModel,
    state: RemoteState,
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
    val currentPosition = (position(model, 100) + LYRIC_VISUAL_LEAD_MS).coerceAtLeast(0)
    val lyrics = state.lyrics?.takeIf { it.occurrenceId == current?.occurrenceId && it.level > 0 }
    val lyricsMayBeAvailable = current != null && (lyrics != null || (state.lyrics == null && state.lyricsIssue == null))

    BoxWithConstraints(Modifier.fillMaxSize().padding(horizontal = 28.dp, vertical = 24.dp)) {
        val horizontal = maxWidth >= 460.dp
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Now playing", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
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
            if (current == null) {
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Text("Nothing is playing", style = MaterialTheme.typography.titleLarge)
                }
            } else {
                if (horizontal) {
                    Row(
                        Modifier.weight(1f).fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(24.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        HomeArtwork(state, current.occurrenceId, current.song.artworkUrl)
                        HomeTrackIdentity(current, state.profile?.remoteId, Modifier.weight(1f))
                    }
                } else {
                    Column(
                        Modifier.weight(1f).fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically),
                    ) {
                        HomeArtwork(state, current.occurrenceId, current.song.artworkUrl)
                        HomeTrackIdentity(current, state.profile?.remoteId, Modifier.fillMaxWidth())
                    }
                }
                PlaybackTimeline(model, state, currentPosition)
            }
        }
    }
}

@Composable
private fun HomeArtwork(
    state: RemoteState,
    occurrenceId: String,
    artworkUrl: String?,
) {
    MotionArtwork(
        video = state.motion?.takeIf { it.occurrenceId == occurrenceId }?.file,
        playing = state.snapshot?.playing == true,
        modifier = Modifier.size(184.dp),
    ) {
        Artwork(artworkUrl, Modifier.fillMaxSize())
    }
}

@Composable
private fun HomeTrackIdentity(
    current: app.cadenza.remote.data.CurrentPlayback,
    remoteId: String?,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            current.song.title,
            style = MaterialTheme.typography.headlineSmall,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            current.song.artist,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        current.song.album.takeIf(String::isNotBlank)?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (current.requesterName.isNotBlank()) {
            val requester = if (remoteId != null && current.requestedBy == remoteId) "you" else current.requesterName
            Text(
                "Requested by $requester",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
