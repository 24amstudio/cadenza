package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
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
import app.cadenza.remote.RemoteModel
import app.cadenza.remote.RemoteState
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
            enabled = mayInterruptPlayback(state) && current.song.durationMs != null && "playback.seek" !in state.pending,
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(duration(if (dragging >= 0) dragging.toLong() else currentPosition))
            Text(duration(current.song.durationMs))
        }
    }
}

@Composable
internal fun PlaybackTransport(
    model: RemoteModel,
    state: RemoteState,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
    leadingContent: (@Composable () -> Unit)? = null,
) {
    val snapshot = state.snapshot ?: return
    val current = snapshot.current ?: return
    val mayInterrupt = mayInterruptPlayback(state)
    val playback = if (snapshot.playing) "playback.pause" else "playback.resume"
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        leadingContent?.invoke()
        if (leadingContent != null) Spacer(Modifier.size(if (compact) 8.dp else 12.dp))
        IconButton(
            onClick = {
                model.command(
                    JSONObject().put("kind", "playback.previous").put("occurrence_id", current.occurrenceId),
                    "playback.previous",
                )
            },
            enabled = mayInterrupt && "playback.previous" !in state.pending,
        ) {
            if ("playback.previous" in state.pending) {
                CircularProgressIndicator(Modifier.size(24.dp).semantics { contentDescription = "Previous song pending" })
            } else {
                Icon(cadenzaVector(CadenzaIcon.PREVIOUS), "Previous song")
            }
        }
        Spacer(Modifier.size(if (compact) 8.dp else 12.dp))
        FilledIconButton(
            onClick = { model.command(JSONObject().put("kind", playback).put("occurrence_id", current.occurrenceId), playback) },
            enabled = state.connected && playback !in state.pending,
            modifier = Modifier.size(if (compact) 56.dp else 72.dp),
        ) {
            if (playback in state.pending) {
                CircularProgressIndicator(Modifier.size(28.dp), color = MaterialTheme.colorScheme.onPrimary)
            } else {
                Icon(
                    cadenzaVector(if (snapshot.playing) CadenzaIcon.PAUSE else CadenzaIcon.PLAY),
                    if (snapshot.playing) "Pause in Cadenza Host" else "Resume in Cadenza Host",
                    Modifier.size(if (compact) 28.dp else 36.dp),
                )
            }
        }
        Spacer(Modifier.size(if (compact) 8.dp else 12.dp))
        IconButton(
            onClick = {
                model.command(
                    JSONObject().put("kind", "playback.skip").put("occurrence_id", current.occurrenceId),
                    "playback.skip",
                )
            },
            enabled = mayInterrupt && "playback.skip" !in state.pending,
        ) {
            if ("playback.skip" in state.pending) {
                CircularProgressIndicator(Modifier.size(24.dp).semantics { contentDescription = "Next song pending" })
            } else {
                Icon(cadenzaVector(CadenzaIcon.NEXT), "Next song")
            }
        }
    }
}
