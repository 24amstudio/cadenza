package app.cadenza.remote.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.model.RemoteModel
import org.json.JSONObject

/**
 * Chooses where a music video's karaoke line is drawn: over Music's window on this Mac, or on a Cast device. Only one of
 * the two shows it, so the choice is exclusive. A Cast device shows it only once the custom receiver is built.
 */
@Composable
internal fun LyricTargetChooser(
    model: RemoteModel,
    videoOutput: String?,
    lipSyncOffsetMs: Int?,
    enabled: Boolean,
    modifier: Modifier = Modifier,
) {
    val selected = videoOutput ?: "host_display"
    val offset = lipSyncOffsetMs ?: 0
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Karaoke lyrics on", style = MaterialTheme.typography.labelLarge)
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            listOf("host_display" to "This Mac", "cast_transmitter" to "Cast device").forEach { (target, label) ->
                FilterChip(
                    selected = selected == target,
                    onClick = {
                        model.command(
                            JSONObject().put("kind", "video.output").put("video_output", target),
                            "video.output",
                        )
                    },
                    label = { Text(label) },
                    enabled = enabled,
                )
            }
        }
        Text("AVR lip-sync offset, $offset ms", style = MaterialTheme.typography.labelLarge)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(-50 to "Earlier 50 ms", 50 to "Later 50 ms").forEach { (step, label) ->
                OutlinedButton(
                    onClick = {
                        val next = (offset + step).coerceIn(-500, 500)
                        model.command(
                            JSONObject().put("kind", "lip_sync.offset").put("lip_sync_offset_ms", next),
                            "lip_sync.offset",
                        )
                    },
                    enabled = enabled,
                ) { Text(label) }
            }
        }
    }
}
