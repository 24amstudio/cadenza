package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.BuildConfig
import app.cadenza.remote.RemoteModel
import app.cadenza.remote.RemoteState
import app.cadenza.remote.data.ThemePreference

@Composable
fun SettingsScreen(
    model: RemoteModel,
    state: RemoteState,
    installUpdate: (String) -> Unit,
) {
    var name by rememberSaveable(state.clientName) { mutableStateOf(state.clientName) }
    var theme by rememberSaveable(state.theme) { mutableStateOf(state.theme) }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        ScreenHeader("Settings", state)
        Text("This Remote", style = MaterialTheme.typography.titleLarge)
        OutlinedTextField(name, { name = it.take(80) }, label = { Text("Remote name") }, singleLine = true)
        Text("Theme", style = MaterialTheme.typography.titleLarge)
        ThemePreference.entries.forEach { option ->
            FilterChip(selected = theme == option, onClick = { theme = option }, label = { Text(option.label) })
        }
        ActionButton(
            "Save preferences",
            pending = state.savingPreferences,
            enabled = name.isNotBlank(),
        ) { model.savePreferences(name, theme) }
        Text("Host", style = MaterialTheme.typography.titleLarge)
        Text(state.profile?.name ?: "Not paired")
        state.profile?.let { Text(it.address + ":" + it.port) }
        ActionButton("Reconnect", pending = state.connecting, onClick = model::connect)
        ActionButton("Pair again", onClick = model::beginPairing)
        Text("Request permissions", style = MaterialTheme.typography.titleLarge)
        Text(
            if (state.snapshot?.allowCrossRemoteEdits == true) {
                "Remotes can change each other’s requests. Mac-originated playback remains controlled by Host."
            } else {
                "Each Remote can change only its own requests. Other people’s current songs are protected too."
            },
        )
        Text("Change this setting on Cadenza Host.")
        Text("App updates", style = MaterialTheme.typography.titleLarge)
        Text("Cadenza Remote " + BuildConfig.VERSION_NAME)
        Text(BuildConfig.BUILD_PROFILE + " · " + BuildConfig.BUILD_ID)
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
        Text("Updates preserve your pairing and local listening history. Android may ask you to approve installation.")
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
