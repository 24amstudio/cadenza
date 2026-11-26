package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import org.json.JSONObject

internal fun mayInterruptPlayback(state: RemoteState): Boolean {
    val snapshot = state.snapshot ?: return false
    if (!state.connected) return false
    val requester = snapshot.current?.requestedBy
    return requester == null || requester == state.profile?.remoteId || snapshot.allowCrossRemoteEdits
}

@Composable
internal fun PlaybackTimeline(
    model: RemoteModel,
    state: RemoteState,
    currentPosition: Long,
    modifier: Modifier = Modifier,
) {
    val current = state.snapshot?.current ?: return
    var dragging by remember(current.occurrenceId) { mutableFloatStateOf(-1f) }
    val slider =
        remember(current.occurrenceId, current.song.durationMs) {
            SliderState(trackRange = 0f..(current.song.durationMs ?: 1).coerceAtLeast(1).toFloat())
        }
    slider.value = if (dragging >= 0) dragging else currentPosition.toFloat()
    Column(modifier) {
        Slider(
            state = slider,
            onValueChange = { dragging = it },
            modifier = Modifier.semantics { contentDescription = "Playback position" },
            onValueChangeFinished = {
                val target = dragging
                dragging = -1f
                model.command(
                    JSONObject()
                        .put("kind", "playback.seek")
                        .put("occurrence_id", current.occurrenceId)
                        .put("position_ms", target.coerceAtLeast(0f).toLong()),
                    "playback.seek",
                )
            },
            enabled = mayInterruptPlayback(state) && current.song.durationMs != null && !current.isLiveRadio,
        )
        if (current.isLiveRadio) {
            // A radio stream has no length to seek within, so its timeline shows a live label instead of times.
            Text(
                "Live",
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.semantics { contentDescription = "Live radio" },
            )
        } else {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(duration(if (dragging >= 0) dragging.toLong() else currentPosition))
                Text(duration(current.song.durationMs))
            }
        }
    }
}

// One slot per control. Slots share the row evenly, so the group shrinks with the column instead of clipping, and
// the row stops growing once the controls are comfortably spaced so a wide column keeps them together.
private const val SLOT_MAX_COMPACT_DP = 76
private const val SLOT_MAX_DP = 88

@Composable
private fun RowScope.TransportSlot(content: @Composable () -> Unit) {
    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { content() }
}

@Composable
internal fun PlaybackTransport(
    model: RemoteModel,
    state: RemoteState,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
    // A full-width group spreads its slots across the whole row instead of stopping at the slot maximum.
    fillWidth: Boolean = false,
    leadingContent: (@Composable () -> Unit)? = null,
    trailingContent: (@Composable () -> Unit)? = null,
) {
    val snapshot = state.snapshot ?: return
    val current = snapshot.current ?: return
    val mayInterrupt = mayInterruptPlayback(state)
    val playback = if (snapshot.playing) "playback.pause" else "playback.resume"
    val slots = 3 + (if (leadingContent != null) 1 else 0) + (if (trailingContent != null) 1 else 0)
    val group =
        if (fillWidth) {
            Modifier.fillMaxWidth()
        } else {
            Modifier.widthIn(max = (slots * if (compact) SLOT_MAX_COMPACT_DP else SLOT_MAX_DP).dp).fillMaxWidth()
        }
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Row(
            group,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            leadingContent?.let { TransportSlot(it) }
            TransportSlot {
                IconButton(
                    onClick = {
                        model.command(
                            JSONObject().put("kind", "playback.previous").put("occurrence_id", current.occurrenceId),
                            "playback.previous",
                        )
                    },
                    enabled = mayInterrupt,
                ) {
                    Icon(cadenzaVector(CadenzaIcon.PREVIOUS), "Previous song")
                }
            }
            TransportSlot {
                FilledIconButton(
                    onClick = { model.command(JSONObject().put("kind", playback).put("occurrence_id", current.occurrenceId), playback) },
                    enabled = state.connected,
                    modifier = Modifier.size(if (compact) 56.dp else 72.dp),
                ) {
                    Icon(
                        cadenzaVector(if (snapshot.playing) CadenzaIcon.PAUSE else CadenzaIcon.PLAY),
                        if (snapshot.playing) "Pause in Cadenza Host" else "Resume in Cadenza Host",
                        Modifier.size(if (compact) 28.dp else 36.dp),
                    )
                }
            }
            TransportSlot {
                IconButton(
                    onClick = {
                        model.command(
                            JSONObject().put("kind", "playback.skip").put("occurrence_id", current.occurrenceId),
                            "playback.skip",
                        )
                    },
                    enabled = mayInterrupt,
                ) {
                    Icon(cadenzaVector(CadenzaIcon.NEXT), "Next song")
                }
            }
            trailingContent?.let { TransportSlot(it) }
        }
    }
}

/** Opens the lyrics. Its place in the transport is the first slot, before Previous. */
@Composable
internal fun LyricsButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    IconButton(onClick = onClick, modifier = modifier) {
        Icon(cadenzaVector(CadenzaIcon.LYRICS), contentDescription = "Lyrics")
    }
}

/**
 * The tablet Now Playing controls as one balanced group: Lyrics (only when the song has lyrics), Previous,
 * Play/Pause, Next and Favorite. Shuffle and repeat, when the Host offers them, sit in a row of their own below.
 */
@Composable
internal fun TabletTransport(
    model: RemoteModel,
    state: RemoteState,
    lyrics: (@Composable () -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val song = state.snapshot?.current?.song ?: return
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        PlaybackTransport(
            model,
            state,
            compact = true,
            leadingContent = lyrics,
            trailingContent = { FavoriteIconButton(model, state, song) },
        )
        PlaybackModeRow(model, state)
    }
}
