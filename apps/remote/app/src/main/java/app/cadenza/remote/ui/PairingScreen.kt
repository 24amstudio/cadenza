package app.cadenza.remote.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.core.content.ContextCompat
import app.cadenza.remote.RemoteModel
import app.cadenza.remote.RemoteState
import kotlinx.coroutines.launch

@Composable
fun PairingScreen(
    model: RemoteModel,
    state: RemoteState,
) {
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    var text by rememberSaveable { mutableStateOf("") }
    var name by rememberSaveable { mutableStateOf(state.clientName) }
    var scanning by rememberSaveable { mutableStateOf(false) }
    val cameraPermission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) scanning = true else model.showError("Camera unavailable", "Paste pairing details from Cadenza Host instead.")
        }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        ScreenHeader("Pair with Cadenza Host", state)
        Text("Open Cadenza Host and choose Pair a Remote. Both devices need access to the same local network.")
        OutlinedTextField(name, { name = it.take(80) }, Modifier.fillMaxWidth(), label = { Text("This Remote’s name") })
        ActionButton("Scan pairing QR", enabled = !state.connecting) {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                scanning = true
            } else {
                cameraPermission.launch(Manifest.permission.CAMERA)
            }
        }
        OutlinedTextField(
            text,
            { text = it.take(4_096) },
            Modifier.fillMaxWidth(),
            label = { Text("Pairing details") },
            minLines = 4,
            maxLines = 8,
        )
        TextButton(onClick = {
            scope.launch {
                text =
                    clipboard
                        .getClipEntry()
                        ?.clipData
                        ?.getItemAt(0)
                        ?.coerceToText(context)
                        ?.toString()
                        ?.take(4_096)
                        .orEmpty()
            }
        }) { Text("Paste pairing details") }
        ActionButton("Pair", pending = state.connecting, enabled = text.isNotBlank() && name.isNotBlank()) { model.pair(text, name) }
    }
    if (scanning) {
        Dialog(onDismissRequest = { scanning = false }) {
            Column {
                QrScanner(
                    onCode = { code ->
                        text = code
                        scanning = false
                    },
                    onError = { message ->
                        scanning = false
                        model.showError("Could not scan QR", message)
                    },
                )
                TextButton(onClick = { scanning = false }) { Text("Cancel") }
            }
        }
    }
}
