package app.cadenza.remote.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.AudioOutput
import app.cadenza.remote.data.CastRouteStatus
import app.cadenza.remote.data.CastState
import app.cadenza.remote.model.RemoteModel
import org.json.JSONObject

/**
 * Where Music's audio plays. A button shows the current output and opens a sheet that lists this Mac, AirPlay, and the
 * Google Cast and Cadenza TV receivers. Choosing a receiver routes the audio there, and choosing the one that is playing
 * stops it. The Host's route line sits under the button.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun OutputChooser(
    model: RemoteModel,
    outputs: List<AudioOutput>,
    cast: CastState?,
    enabled: Boolean,
    modifier: Modifier = Modifier,
) {
    var sheetOpen by rememberSaveable { mutableStateOf(false) }
    val sending = cast?.transmit?.takeIf { it.state == "starting" || it.state == "transmitting" }
    val playingStage = cast?.stages?.firstOrNull { it.transmitting }
    val sendingLabel =
        sending?.device?.let { device -> cast.devices.firstOrNull { it.name == device }?.label ?: device }
    val label =
        when {
            playingStage != null -> "Cadenza TV: ${playingStage.name}"
            sending != null -> "Google Cast: ${sendingLabel.orEmpty()}"
            else -> outputs.firstOrNull { it.isDefault }?.name ?: "No output"
        }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        OutlinedButton(
            onClick = { sheetOpen = true },
            enabled = enabled,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Output: $label", maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        (playingStage?.status ?: sending?.status)?.let { RouteStatusLine(it) }
        cast?.transmit?.takeIf { it.state == "failed" }?.reason?.let { reason ->
            Text(reason, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
    }

    if (sheetOpen) {
        ModalBottomSheet(onDismissRequest = { sheetOpen = false }) {
            OutputSheet(model, outputs, cast, enabled, onChosen = { sheetOpen = false })
        }
    }
}

@Composable
private fun OutputSheet(
    model: RemoteModel,
    outputs: List<AudioOutput>,
    cast: CastState?,
    enabled: Boolean,
    onChosen: () -> Unit,
) {
    val sending = cast?.transmit?.takeIf { it.state == "starting" || it.state == "transmitting" }
    val playingStage = cast?.stages?.firstOrNull { it.transmitting }
    val receiving = sending != null || playingStage != null

    fun stopReceiving() {
        sending?.device?.let { sendTransmit(model, it, start = false) }
        playingStage?.let { sendTransmit(model, "stage:${it.receiverId}", start = false) }
    }

    fun selectLocal(output: AudioOutput) {
        if (receiving) stopReceiving()
        model.command(
            JSONObject().put("kind", "audio.selectOutput").put("output", output.id),
            "audio.selectOutput",
        )
        onChosen()
    }

    Column(
        Modifier.padding(start = 24.dp, end = 24.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("Audio output", style = MaterialTheme.typography.titleLarge)
        val thisMac = outputs.filter { it.transport != "airplay" }
        val airPlay = outputs.filter { it.transport == "airplay" }
        if (thisMac.isNotEmpty()) {
            OutputSection("This Mac") {
                thisMac.forEach { output ->
                    val selected = output.isDefault && !receiving
                    OutputRow(output.name, if (selected) "Playing here" else null, selected, enabled) {
                        selectLocal(output)
                    }
                }
            }
        }
        if (airPlay.isNotEmpty()) {
            OutputSection("AirPlay") {
                airPlay.forEach { output ->
                    val selected = output.isDefault && !receiving
                    OutputRow(output.name, if (selected) "Playing here" else null, selected, enabled) {
                        selectLocal(output)
                    }
                }
            }
        }
        if (cast != null && cast.devices.isNotEmpty()) {
            OutputSection("Google Cast") {
                cast.devices.forEach { device ->
                    val active = sending?.device == device.name
                    OutputRow(device.label, if (active) "Sending audio" else null, active, enabled) {
                        sendTransmit(model, device.name, start = !active)
                        onChosen()
                    }
                }
            }
        }
        if (cast != null && (cast.stages.isNotEmpty() || cast.pendingStages.isNotEmpty())) {
            OutputSection("Cadenza TV") {
                cast.pendingStages.forEach { pending ->
                    OutputRow("Approve ${pending.name}", "PIN ${pending.pin}", selected = false, enabled) {
                        model.command(
                            JSONObject().put("kind", "stage.approve").put("pin", pending.pin),
                            "stage.approve",
                        )
                        onChosen()
                    }
                }
                cast.stages.forEach { stage ->
                    val detail = stage.status?.text ?: if (stage.transmitting) "Sending audio" else null
                    OutputRow(stage.name, detail, stage.transmitting, enabled) {
                        sendTransmit(model, "stage:${stage.receiverId}", start = !stage.transmitting)
                        onChosen()
                    }
                }
            }
        }
    }
}

@Composable
private fun OutputSection(
    title: String,
    content: @Composable () -> Unit,
) {
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 8.dp),
    )
    content()
}

@Composable
private fun OutputRow(
    title: String,
    detail: String?,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    val container = if (selected) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh
    val text = if (selected) MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurface
    Column(
        Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 56.dp)
            .background(container, RoundedCornerShape(16.dp))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, color = text)
        detail?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** The Host's route line. A mismatch uses the error color, and a line that cannot be confirmed stays neutral. */
@Composable
private fun RouteStatusLine(status: CastRouteStatus) {
    Text(
        status.text,
        style = MaterialTheme.typography.bodySmall,
        color = if (status.mismatch) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

private fun sendTransmit(
    model: RemoteModel,
    device: String,
    start: Boolean,
) {
    model.command(
        JSONObject().put("kind", "cast.transmit").put("device", device).put("start", start),
        "cast.transmit",
    )
}
