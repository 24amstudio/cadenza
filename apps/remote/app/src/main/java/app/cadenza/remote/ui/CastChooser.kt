package app.cadenza.remote.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.CastState
import app.cadenza.remote.model.RemoteModel
import org.json.JSONObject

/**
 * Sends Music's audio to a Google Cast device. Selecting a device starts sending to it, and selecting the device that is
 * receiving stops the transmission. A failed transmission shows its reason under the devices.
 */
@Composable
internal fun CastChooser(
    model: RemoteModel,
    cast: CastState?,
    enabled: Boolean,
    modifier: Modifier = Modifier,
) {
    if (cast == null || cast.devices.isEmpty()) return

    val transmit = cast.transmit
    val active = transmit?.takeIf { it.state == "starting" || it.state == "transmitting" }

    Column(modifier) {
        Text("Google Cast", style = MaterialTheme.typography.labelLarge)
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            cast.devices.forEach { device ->
                val sending = active?.device == device.name
                FilterChip(
                    selected = sending,
                    onClick = {
                        model.command(
                            JSONObject()
                                .put("kind", "cast.transmit")
                                .put("device", device.name)
                                .put("start", !sending),
                            "cast.transmit",
                        )
                    },
                    label = { Text(device.name) },
                    enabled = enabled,
                )
            }
        }
        if (transmit?.state == "failed") {
            Text(transmit.reason ?: "Cast could not send audio.", style = MaterialTheme.typography.bodySmall)
        }
    }
}
