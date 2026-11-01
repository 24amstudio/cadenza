package app.cadenza.remote.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.cadenza.remote.BuildConfig
import app.cadenza.remote.data.ThemePreference
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.model.checkHostUpdate
import app.cadenza.remote.model.checkUpdates
import app.cadenza.remote.model.dismissChangelog
import app.cadenza.remote.model.hostUpdateMessage
import app.cadenza.remote.model.installHostUpdate
import app.cadenza.remote.model.installing
import app.cadenza.remote.model.showChangelog
import app.cadenza.remote.model.showError
import app.cadenza.remote.updates.Changelog

@Composable
fun SettingsScreen(
    model: RemoteModel,
    state: RemoteState,
    installUpdate: (String) -> Unit,
) {
    var name by rememberSaveable(state.clientName) { mutableStateOf(state.clientName) }
    var theme by rememberSaveable(state.theme) { mutableStateOf(state.theme) }
    var debugOpen by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    val bluetoothPermissions =
        rememberLauncherForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions(),
        ) { permissions ->
            val mode = state.transportMode
            if (mode == "lan" || permissions.values.all { it }) {
                model.reconnectWithTransport(mode)
            } else {
                model.showError(
                    "Bluetooth permission needed",
                    "Allow Nearby devices so Cadenza can connect to this Host over Bluetooth.",
                )
            }
        }

    fun chooseTransport(mode: String) {
        if (mode == "lan" || nearbyDevicesGranted(context)) {
            model.reconnectWithTransport(mode)
        } else {
            bluetoothPermissions.launch(nearbyDevicePermissions)
        }
    }

    if (debugOpen) {
        DebugScreen(state, onBack = { debugOpen = false })
        return
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth >= 760.dp
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = if (wide) 32.dp else 20.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                Modifier.widthIn(max = 1_120.dp).fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                SettingsHeader(state)
                if (wide) {
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(20.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        IdentityCard(
                            name = name,
                            theme = theme,
                            onNameChange = { name = it },
                            onThemeChange = { theme = it },
                            onSave = { model.savePreferences(name, theme) },
                            saving = state.savingPreferences,
                            modifier = Modifier.weight(1f),
                        )
                        HostCard(model, state, Modifier.weight(1f))
                    }
                } else {
                    IdentityCard(
                        name = name,
                        theme = theme,
                        onNameChange = { name = it },
                        onThemeChange = { theme = it },
                        onSave = { model.savePreferences(name, theme) },
                        saving = state.savingPreferences,
                    )
                    HostCard(model, state)
                }
                TransportCard(
                    model = model,
                    state = state,
                    chooseTransport = ::chooseTransport,
                )
                SupportUpdatesCard(model, state, installUpdate, onOpenDebug = { debugOpen = true })
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
}

@Composable
private fun SettingsHeader(state: RemoteState) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("Settings", style = MaterialTheme.typography.headlineLarge)
        Text(
            "Tune this Remote and its connection to Cadenza Host.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        ConnectionStatus(state)
    }
}

@Composable
private fun IdentityCard(
    name: String,
    theme: ThemePreference,
    onNameChange: (String) -> Unit,
    onThemeChange: (ThemePreference) -> Unit,
    onSave: () -> Unit,
    saving: Boolean,
    modifier: Modifier = Modifier,
) {
    SettingsCard(
        modifier = modifier,
        icon = CadenzaIcon.SETTINGS,
        title = "This Remote",
        supporting = "Set the name and appearance used on this device.",
    ) {
        OutlinedTextField(
            value = name,
            onValueChange = { onNameChange(it.take(80)) },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Remote name") },
            singleLine = true,
        )
        Text("Theme", style = MaterialTheme.typography.labelLarge)
        ChoiceRow(
            options = ThemePreference.entries.map { it.name to it.label },
            selected = theme.name,
            onSelected = { value -> onThemeChange(ThemePreference.valueOf(value)) },
        )
        ActionButton(
            "Save preferences",
            modifier = Modifier.fillMaxWidth(),
            pending = saving,
            enabled = name.isNotBlank(),
            onClick = onSave,
        )
    }
}

@Composable
private fun HostCard(
    model: RemoteModel,
    state: RemoteState,
    modifier: Modifier = Modifier,
) {
    SettingsCard(
        modifier = modifier,
        icon = CadenzaIcon.MUSIC,
        title = "Cadenza Host",
        supporting = "The Mac that controls Music for this Remote.",
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(state.profile?.name ?: "Not paired", style = MaterialTheme.typography.titleMedium)
            state.profile?.let { Text("${it.address}:${it.port}", color = MaterialTheme.colorScheme.onSurfaceVariant) }
            ConnectionStatus(state)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ActionButton("Reconnect", modifier = Modifier.weight(1f), pending = state.connecting, onClick = model::connect)
            TextButton(onClick = model::beginPairing, modifier = Modifier.weight(1f)) { Text("Pair again") }
        }
        if ("host.update" in state.capabilities) {
            hostUpdateMessage(state.hostUpdate)?.let { message ->
                Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ActionButton(
                    if (state.hostUpdate?.state == "ready") "Install Host update" else "Check and install Host update",
                    modifier = Modifier.fillMaxWidth(),
                    pending = state.hostUpdate?.state == "checking" || state.hostUpdate?.state == "requesting" || state.hostUpdate?.state == "installing",
                    enabled = state.connected && state.hostUpdate?.state != "installing",
                ) {
                    if (state.hostUpdate?.state == "ready") model.installHostUpdate() else model.checkHostUpdate()
                }
            }
        }
        Text(
            if (state.snapshot?.allowCrossRemoteEdits == true) {
                "Remotes can change each other's requests. Host-originated playback remains controlled by Cadenza Host."
            } else {
                "Each Remote can change only its own requests. Other people's current songs are protected too."
            },
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyMedium,
        )
        Text("Change this setting in Cadenza Host.", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun TransportCard(
    model: RemoteModel,
    state: RemoteState,
    chooseTransport: (String) -> Unit,
) {
    SettingsCard(
        icon = CadenzaIcon.WIFI,
        title = "Connection transport",
        supporting = "Choose the path this Remote uses to reach Cadenza Host.",
    ) {
        Text(
            "Choose one connection mode. Hybrid keeps Wi-Fi and Bluetooth available and selects the healthier path automatically.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        TransportPathIndicator(state)
        Text("Connection mode", style = MaterialTheme.typography.labelLarge)
        ChoiceRow(
            options = listOf("lan" to "Wi-Fi / LAN", "ble" to "Bluetooth", "hybrid" to "Hybrid"),
            selected = state.transportMode,
            onSelected = chooseTransport,
        )
        ActionButton(
            "Reconnect using ${transportModeLabel(state.transportMode)}",
            modifier = Modifier.fillMaxWidth(),
            pending = state.connecting,
            enabled = state.profile != null,
            onClick = { chooseTransport(state.transportMode) },
        )
        HorizontalDivider()
        Text("Transport preference", style = MaterialTheme.typography.labelLarge)
        Text(
            "The Host blends this preference with its own limits and priorities.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyMedium,
        )
        ChoiceRow(
            options =
                listOf(
                    "latency" to "Latency",
                    "balanced" to "Balanced",
                    "remote_efficiency" to "Battery",
                    "reliability" to "Reliability",
                ),
            selected = state.transportPreference,
            onSelected = model::setTransportPreference,
        )
        state.effectiveTransport?.let { decision ->
            Text(
                "Negotiated primary path: " +
                    when (decision.selected) {
                        "ble" -> "Bluetooth"
                        "lan", "wifi", "ethernet" -> "Wi-Fi / LAN"
                        else -> "Unavailable"
                    },
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                "Host ${decision.hostPreference} · Remote ${decision.remotePreference ?: state.transportPreference} · " +
                    "${decision.confidence} confidence",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

private fun transportModeLabel(mode: String): String =
    when (mode) {
        "ble" -> "Bluetooth"
        "hybrid" -> "Hybrid"
        else -> "Wi-Fi / LAN"
    }

@Composable
private fun SupportUpdatesCard(
    model: RemoteModel,
    state: RemoteState,
    installUpdate: (String) -> Unit,
    onOpenDebug: () -> Unit,
) {
    var installAfterCheck by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state.updateBusy, state.stagedUpdate) {
        if (installAfterCheck && !state.updateBusy) {
            installAfterCheck = false
            state.stagedUpdate?.let(installUpdate)
        }
    }
    SettingsCard(
        icon = CadenzaIcon.ANALYTICS,
        title = "Support and updates",
        supporting = "Diagnostics and release tools stay on this device.",
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Diagnostics", style = MaterialTheme.typography.titleMedium)
                Text("Inspect device usage and recent errors.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            TextButton(onClick = onOpenDebug) { Text("Open Debug") }
        }
        HorizontalDivider()
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Cadenza Remote ${BuildConfig.VERSION_NAME}", style = MaterialTheme.typography.titleMedium)
            Text(
                "${BuildConfig.BUILD_PROFILE} · ${BuildConfig.BUILD_ID}",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = { model.showChangelog() }, modifier = Modifier.weight(1f)) {
                    Text("Changes in this build")
                }
                TextButton(
                    onClick = { model.showChangelog(compare = true) },
                    modifier = Modifier.weight(1f),
                    enabled = !state.comparingChanges,
                ) { Text("Compare published changes") }
            }
            ActionButton(
                if (state.stagedUpdate == null) "Check and install updates" else "Install update",
                modifier = Modifier.fillMaxWidth(),
                pending = state.updateBusy || state.installationBusy,
                enabled = BuildConfig.AUTOMATIC_UPDATES,
                onClick = {
                    state.stagedUpdate?.let(installUpdate)
                        ?: run {
                            installAfterCheck = true
                            model.checkUpdates()
                        }
                },
            )
            if (!BuildConfig.AUTOMATIC_UPDATES) {
                Text("Automatic updates are disabled in this build.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun SettingsCard(
    icon: CadenzaIcon,
    title: String,
    supporting: String,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        tonalElevation = 1.dp,
    ) {
        Column(
            Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            content = {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Surface(
                        Modifier.size(44.dp),
                        shape = MaterialTheme.shapes.large,
                        color = MaterialTheme.colorScheme.primaryContainer,
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                cadenzaVector(icon),
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onPrimaryContainer,
                                modifier = Modifier.size(22.dp),
                            )
                        }
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(title, style = MaterialTheme.typography.titleLarge)
                        Text(supporting, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                content()
            },
        )
    }
}

@Composable
private fun ChoiceRow(
    options: List<Pair<String, String>>,
    selected: String,
    onSelected: (String) -> Unit,
) {
    Row(
        Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        options.forEach { (value, label) ->
            FilterChip(
                selected = selected == value,
                onClick = { onSelected(value) },
                label = { Text(label) },
            )
        }
    }
}
