package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.IconToggleButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import org.json.JSONObject

// Shuffle and repeat appear only when the Host says Music's modes can be controlled.
internal fun playbackModesAvailable(state: RemoteState): Boolean = "playback.modes" in state.capabilities && state.snapshot != null

internal fun shuffleSlot(
    model: RemoteModel,
    state: RemoteState,
): (@Composable () -> Unit)? = if (playbackModesAvailable(state)) ({ ShuffleButton(model, state) }) else null

internal fun repeatSlot(
    model: RemoteModel,
    state: RemoteState,
): (@Composable () -> Unit)? = if (playbackModesAvailable(state)) ({ RepeatButton(model, state) }) else null

/** Shuffle and repeat side by side, centred. Nothing is drawn when the Host does not offer them. */
@Composable
internal fun PlaybackModeRow(
    model: RemoteModel,
    state: RemoteState,
) {
    if (!playbackModesAvailable(state)) return
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
        ShuffleButton(model, state)
        RepeatButton(model, state)
    }
}

internal fun nextRepeatMode(mode: String): String =
    when (mode) {
        "off" -> "all"
        "all" -> "one"
        else -> "off"
    }

@Composable
internal fun ShuffleButton(
    model: RemoteModel,
    state: RemoteState,
) {
    val enabled = state.snapshot?.shuffle == true
    ModeToggle(
        checked = enabled,
        label = "Shuffle",
        status = if (enabled) "On" else "Off",
        icon = CadenzaIcon.SHUFFLE,
        enabled = state.connected,
    ) {
        model.command(JSONObject().put("kind", "playback.shuffle").put("enabled", !enabled), "playback.shuffle")
    }
}

@Composable
internal fun RepeatButton(
    model: RemoteModel,
    state: RemoteState,
) {
    val mode = state.snapshot?.repeat ?: "off"
    ModeToggle(
        checked = mode != "off",
        label = "Repeat",
        status =
            when (mode) {
                "all" -> "All songs"
                "one" -> "This song"
                else -> "Off"
            },
        icon = if (mode == "one") CadenzaIcon.REPEAT_ONE else CadenzaIcon.REPEAT,
        enabled = state.connected,
    ) {
        model.command(JSONObject().put("kind", "playback.repeat").put("mode", nextRepeatMode(mode)), "playback.repeat")
    }
}

@Composable
private fun ModeToggle(
    checked: Boolean,
    label: String,
    status: String,
    icon: CadenzaIcon,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    IconToggleButton(
        checked = checked,
        onCheckedChange = { onClick() },
        enabled = enabled,
        modifier = Modifier.size(48.dp),
        colors =
            IconButtonDefaults.iconToggleButtonColors(
                checkedContainerColor = MaterialTheme.colorScheme.secondaryContainer,
                checkedContentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
            ),
    ) {
        Icon(cadenzaVector(icon), contentDescription = "$label: $status", modifier = Modifier.size(24.dp))
    }
}
