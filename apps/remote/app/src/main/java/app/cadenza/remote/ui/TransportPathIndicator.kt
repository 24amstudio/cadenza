package app.cadenza.remote.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.TransportPathStatus
import app.cadenza.remote.model.RemoteState

@Composable
fun TransportPathIndicator(
    state: RemoteState,
    modifier: Modifier = Modifier,
) {
    val paths = state.transportPaths
    val livePaths = paths.filter { it.state == "connected" || it.state == "degraded" }
    val title =
        when {
            livePaths.isEmpty() && state.connecting -> "Connecting over ${modeLabel(state.transportMode)}"
            livePaths.isEmpty() && state.connected -> "Connected; path pending"
            livePaths.isEmpty() -> "Transport unavailable"
            livePaths.size == 1 -> "Connected over ${transportLabel(livePaths.single().transport)}"
            else -> "Connected over multiple paths"
        }
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Column(
            Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(
                    cadenzaVector(
                        when {
                            livePaths.size > 1 -> CadenzaIcon.BIDIRECTIONAL
                            livePaths.singleOrNull()?.transport == "ble" -> CadenzaIcon.BLUETOOTH
                            livePaths.singleOrNull() != null -> CadenzaIcon.WIFI
                            state.connecting && state.transportMode == "ble" -> CadenzaIcon.BLUETOOTH
                            state.connecting && state.transportMode == "hybrid" -> CadenzaIcon.BIDIRECTIONAL
                            else -> CadenzaIcon.WIFI_OFF
                        },
                    ),
                    contentDescription = null,
                    tint =
                        if (livePaths.isEmpty()) {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        } else {
                            MaterialTheme.colorScheme.primary
                        },
                    modifier = Modifier.size(24.dp),
                )
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.titleMedium)
                    Text(
                        when {
                            livePaths.isEmpty() && state.connecting ->
                                if (state.transportMode == "ble") {
                                    "Scanning for the nearby Cadenza Host."
                                } else {
                                    "Waiting for the Host to accept a path."
                                }
                            livePaths.isEmpty() && state.connected -> "Host connected; waiting for path details."
                            livePaths.isEmpty() -> state.connectionIssue ?: "Connect over Wi-Fi or Bluetooth to control Music."
                            else -> "Live control channel · sending and receiving"
                        },
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
            if (paths.isNotEmpty()) {
                Row(
                    Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    paths.forEach { path ->
                        TransportPathChip(
                            path = path,
                            selected = path.transport == state.effectiveTransport?.selected,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TransportPathChip(
    path: TransportPathStatus,
    selected: Boolean,
) {
    val active = path.state == "connected" || path.state == "degraded"
    val stateLabel =
        when (path.state) {
            "connected" -> "Connected"
            "degraded" -> "Degraded"
            "connecting" -> "Connecting"
            else -> "Unavailable"
        }
    Surface(
        color = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = MaterialTheme.shapes.medium,
        modifier =
            Modifier.semantics {
                contentDescription = "${transportLabel(path.transport)}: $stateLabel"
            },
    ) {
        Row(
            Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(
                cadenzaVector(if (path.transport == "ble") CadenzaIcon.BLUETOOTH else CadenzaIcon.WIFI),
                contentDescription = null,
                tint = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(18.dp),
            )
            Text(transportLabel(path.transport), style = MaterialTheme.typography.labelLarge)
            Text(stateLabel, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (active) {
                Icon(
                    cadenzaVector(CadenzaIcon.BIDIRECTIONAL),
                    contentDescription = "Sending and receiving",
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}

private fun transportLabel(transport: String): String =
    when (transport) {
        "ble" -> "Bluetooth"
        "wifi", "ethernet" -> transport.replaceFirstChar(Char::uppercaseChar)
        else -> "Wi-Fi / LAN"
    }

private fun modeLabel(mode: String): String =
    when (mode) {
        "ble" -> "Bluetooth"
        "hybrid" -> "Wi-Fi and Bluetooth"
        else -> "Wi-Fi / LAN"
    }
