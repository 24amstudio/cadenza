package app.cadenza.remote.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import app.cadenza.remote.BuildConfig
import app.cadenza.remote.RemoteModel
import app.cadenza.remote.RemoteState
import app.cadenza.remote.beginPairing
import app.cadenza.remote.checkUpdates
import app.cadenza.remote.data.ThemePreference
import app.cadenza.remote.data.TransportMethodRegistry
import app.cadenza.remote.dismissChangelog
import app.cadenza.remote.showChangelog
import app.cadenza.remote.showError

@Composable
fun SettingsScreen(
    model: RemoteModel,
    state: RemoteState,
    installUpdate: (String) -> Unit,
) {
    var name by rememberSaveable(state.clientName) { mutableStateOf(state.clientName) }
    var theme by rememberSaveable(state.theme) { mutableStateOf(state.theme) }
    var debugOpen by rememberSaveable { mutableStateOf(false) }
    var pendingTransport by rememberSaveable { mutableStateOf<String?>(null) }
    var showTransportDialog by rememberSaveable { mutableStateOf(false) }
    var draftTransportMethods by rememberSaveable { mutableStateOf(TransportMethodRegistry.selectedFor(state.transportMode)) }
    val context = LocalContext.current
    val bluetoothPermissions =
        rememberLauncherForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions(),
        ) { permissions ->
            val mode = pendingTransport
            pendingTransport = null
            if (mode != null && permissions.values.all { it }) {
                model.setTransportMode(mode)
            } else if (mode != null) {
                model.showError("Bluetooth permission needed", "Allow Nearby devices so Cadenza can connect to this Host over Bluetooth.")
            }
        }

    fun chooseTransport(mode: String) {
        if (mode == "lan" || (
                ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
                    ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
            )
        ) {
            model.setTransportMode(mode)
        } else {
            pendingTransport = mode
            bluetoothPermissions.launch(
                arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT),
            )
        }
    }
    if (debugOpen) {
        DebugScreen(state, onBack = { debugOpen = false })
        return
    }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        ScreenHeader("Settings", state)
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("This Remote", style = MaterialTheme.typography.titleLarge)
                Text("Choose the name and appearance used on this device.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                OutlinedTextField(name, { name = it.take(80) }, label = { Text("Remote name") }, singleLine = true)
                Text("Theme", style = MaterialTheme.typography.titleLarge)
                ThemePreference.entries.forEach { option ->
                    FilterChip(selected = theme == option, onClick = { theme = option }, label = { Text(option.label) })
                }
                Text("Connection transport", style = MaterialTheme.typography.titleLarge)
                Text(
                    "Choose the path this Remote uses for its Host session. Hybrid keeps Wi-Fi and Bluetooth connected together.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                ActionButton("Add connection method") {
                    draftTransportMethods = TransportMethodRegistry.selectedFor(state.transportMode)
                    showTransportDialog = true
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = state.transportMode == "lan",
                        onClick = { chooseTransport("lan") },
                        label = { Text("Wi-Fi / LAN") },
                    )
                    FilterChip(
                        selected = state.transportMode == "ble",
                        onClick = { chooseTransport("ble") },
                        label = { Text("Bluetooth") },
                    )
                    FilterChip(
                        selected = state.transportMode == "hybrid",
                        onClick = { chooseTransport("hybrid") },
                        label = { Text("Hybrid") },
                    )
                }
                Text("Transport preference", style = MaterialTheme.typography.titleLarge)
                Text(
                    "The Host blends this preference with its own limits and priorities.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(
                        "latency" to "Latency",
                        "balanced" to "Balanced",
                        "remote_efficiency" to "Battery",
                        "reliability" to "Reliability",
                    ).forEach { (value, label) ->
                        FilterChip(
                            selected = state.transportPreference == value,
                            onClick = { model.setTransportPreference(value) },
                            label = { Text(label) },
                        )
                    }
                }
                state.effectiveTransport?.let { decision ->
                    Text("Effective path: ${decision.selected ?: "Unavailable"}")
                    Text(
                        "Host policy: ${decision.hostPreference} · " +
                            "Remote policy: ${decision.remotePreference ?: state.transportPreference} · " +
                            "${decision.policyMode} · ${decision.confidence} confidence",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(decision.reason, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                ActionButton("Save preferences", pending = state.savingPreferences, enabled = name.isNotBlank()) {
                    model.savePreferences(name, theme)
                }
            }
        }
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Support", style = MaterialTheme.typography.titleLarge)
                Text(
                    "Inspect device usage and recent errors without sending diagnostics anywhere.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                ActionButton("Open Debug") { debugOpen = true }
            }
        }
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Cadenza Host", style = MaterialTheme.typography.titleLarge)
                Text(state.profile?.name ?: "Not paired")
                state.profile?.let { Text(it.address + ":" + it.port, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ActionButton("Reconnect", pending = state.connecting, onClick = model::connect)
                    ActionButton("Pair again", onClick = model::beginPairing)
                }
                Text(
                    if (state.snapshot?.allowCrossRemoteEdits == true) {
                        "Remotes can change each other’s requests. Host-originated playback remains controlled by Cadenza Host."
                    } else {
                        "Each Remote can change only its own requests. Other people’s current songs are protected too."
                    },
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text("Change this setting in Cadenza Host.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("App updates", style = MaterialTheme.typography.titleLarge)
                Text("Cadenza Remote " + BuildConfig.VERSION_NAME)
                Text(BuildConfig.BUILD_PROFILE + " · " + BuildConfig.BUILD_ID, color = MaterialTheme.colorScheme.onSurfaceVariant)
                ActionButton("Changes in this build") { model.showChangelog() }
                ActionButton("Compare published changes", pending = state.comparingChanges) { model.showChangelog(compare = true) }
                Text(state.updateConfiguration.repository.ifEmpty { "Configure a GitHub release source in Cadenza Host, then reconnect." })
                ActionButton(
                    "Check for updates",
                    pending = state.updateBusy,
                    enabled = BuildConfig.AUTOMATIC_UPDATES,
                    onClick = { model.checkUpdates() },
                )
                if (!BuildConfig.AUTOMATIC_UPDATES) Text("Automatic updates are disabled in this build.")
                state.stagedUpdate?.let { path ->
                    ActionButton("Install prepared update", pending = state.installationBusy) { installUpdate(path) }
                }
                Text("Updates preserve pairing and listening history. The Android system may ask you to approve installation.")
            }
        }
    }
    state.changelog?.let { notes ->
        AlertDialog(
            onDismissRequest = model::dismissChangelog,
            title = { Text("Changelog") },
            text = { Text(notes, Modifier.verticalScroll(rememberScrollState())) },
            confirmButton = { TextButton(onClick = model::dismissChangelog) { Text("Close") } },
        )
    }
    if (showTransportDialog) {
        AlertDialog(
            onDismissRequest = { showTransportDialog = false },
            title = { Text("Add connection method") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Keep one or both paths connected to this Host.")
                    TransportMethodRegistry.available.forEach { option ->
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Checkbox(
                                checked = option.id in draftTransportMethods,
                                onCheckedChange = { checked ->
                                    draftTransportMethods =
                                        if (checked) {
                                            draftTransportMethods + option.id
                                        } else {
                                            draftTransportMethods - option.id
                                        }
                                },
                            )
                            Column {
                                Text(option.label)
                                Text(option.description, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val mode = TransportMethodRegistry.modeFor(draftTransportMethods)
                    if (mode == null) {
                        model.showError("Choose a connection method", "Select at least one supported connection method.")
                    } else {
                        chooseTransport(mode)
                        showTransportDialog = false
                    }
                }) { Text("Connect") }
            },
            dismissButton = { TextButton(onClick = { showTransportDialog = false }) { Text("Cancel") } },
        )
    }
}
