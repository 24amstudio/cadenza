package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.CurrentPlayback
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import org.json.JSONObject

@Composable
internal fun SingControls(
    model: RemoteModel,
    state: RemoteState,
    current: CurrentPlayback,
) {
    if ("sing.mode" !in state.capabilities) return
    val sing = state.snapshot?.sing ?: return
    val canMix = sing.status == "ready" || sing.status == "active"
    val pendingKeys = model.pending.values.map { it.key }.toSet()
    val pendingEnable = "sing.enable" in pendingKeys
    val pendingDisable = "sing.disable" in pendingKeys
    var vocal by remember(current.occurrenceId) { mutableFloatStateOf(-1f) }
    val slider = remember(current.occurrenceId) { SliderState(trackRange = 0f..100f) }
    var failureDialogDismissed by rememberSaveable(current.occurrenceId) { mutableStateOf(false) }
    LaunchedEffect(sing.status) {
        if (sing.status == "failed") failureDialogDismissed = false
    }
    slider.value = if (vocal >= 0) vocal else sing.vocalPercent.toFloat()
    HorizontalDivider()
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Sing mode", style = MaterialTheme.typography.titleMedium)
            Text(
                when (sing.status) {
                    "active" -> "Vocals and instrumental are mixed on Cadenza Host."
                    "preparing" -> "Preparing local audio processing. First use may download about 456 MB."
                    "failed" -> "Sing could not start. Try again."
                    "unavailable" -> "Start Sing to prepare local audio processing.\nmacOS may ask for audio capture access."
                    else -> "Lower the vocal level for karaoke."
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        Button(
            onClick = {
                val kind = if (sing.status == "active") "sing.disable" else "sing.enable"
                model.command(
                    JSONObject().put("kind", kind).put("occurrence_id", current.occurrenceId),
                    kind,
                )
            },
            enabled = state.connected && sing.status != "preparing" && !pendingEnable && !pendingDisable,
        ) {
            if (pendingEnable || pendingDisable) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            } else {
                Text(if (sing.status == "active") "Turn off" else "Start")
            }
        }
    }
    Slider(
        state = slider,
        onValueChange = { vocal = it },
        modifier = Modifier.semantics { contentDescription = "Sing vocal level" },
        onValueChangeFinished = {
            if (canMix) {
                val target = vocal.coerceAtLeast(0f).toInt()
                vocal = -1f
                model.command(
                    JSONObject()
                        .put("kind", "sing.mix")
                        .put("occurrence_id", current.occurrenceId)
                        .put("vocal_percent", target),
                    "sing.mix",
                )
            }
        },
        enabled = state.connected && canMix && "sing.mix" !in pendingKeys,
    )
    Text(
        "Vocal level ${slider.value.toInt()}%",
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    if (sing.status == "failed" && !failureDialogDismissed) {
        AlertDialog(
            onDismissRequest = { failureDialogDismissed = true },
            title = { Text("Sing couldn't start") },
            text = { Text(sing.issue ?: "Local audio processing is unavailable.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        failureDialogDismissed = true
                        model.command(
                            JSONObject()
                                .put("kind", "sing.enable")
                                .put("occurrence_id", current.occurrenceId),
                            "sing.enable",
                        )
                    },
                    enabled = state.connected && !pendingEnable,
                ) { Text("Retry") }
            },
            dismissButton = {
                TextButton(onClick = { failureDialogDismissed = true }) { Text("Close") }
            },
        )
    }
}
