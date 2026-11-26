package app.cadenza.remote.ui.settings

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.ui.CadenzaIcon
import app.cadenza.remote.ui.SettingsCard

/** Lock-screen motion, silent keep-alive, and the system screen saver. Each row explains the device step it depends on. */
@Composable
internal fun BackgroundCard(
    model: RemoteModel,
    state: RemoteState,
) {
    val context = LocalContext.current
    SettingsCard(
        icon = CadenzaIcon.HOME,
        title = "Background and screens",
        supporting = "What Cadenza keeps running, and what it shows when the screen is off.",
    ) {
        ToggleRow(
            title = "Lock-screen motion artwork",
            body =
                "Shows the album's motion artwork over the lock screen while Host plays. On HarmonyOS, also allow " +
                    "Cadenza to show on the lock screen in App Permissions.",
            label = "Lock-screen motion artwork",
            checked = state.lockScreenMotionArtwork,
            onChange = model::setLockScreenMotionArtwork,
        )
        ToggleRow(
            title = "Silent playback keep-alive",
            body = "Plays silence while Host plays, so HarmonyOS keeps Cadenza connected. It takes no audio focus.",
            label = "Silent playback keep-alive",
            checked = state.silentPlaybackKeepAlive,
            onChange = model::setSilentPlaybackKeepAlive,
        )
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("System screen saver", style = MaterialTheme.typography.titleMedium)
            Text(
                "Shows the song while this tablet charges and Host plays. Set When to start to While charging.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
            Button(onClick = { openScreenSaverSettings(context) }) { Text("Open screen saver settings") }
        }
    }
}

@Composable
private fun ToggleRow(
    title: String,
    body: String,
    label: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(body, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
        }
        Switch(checked = checked, onCheckedChange = onChange, modifier = Modifier.semantics { contentDescription = label })
    }
}

/** Opens the system screen saver page, or the general display page when the device has no dream settings. */
private fun openScreenSaverSettings(context: Context) {
    try {
        context.startActivity(Intent(Settings.ACTION_DREAM_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (error: ActivityNotFoundException) {
        context.startActivity(Intent(Settings.ACTION_DISPLAY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
