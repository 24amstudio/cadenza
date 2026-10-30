package app.cadenza.remote.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.core.content.ContextCompat
import app.cadenza.remote.RemoteModel
import app.cadenza.remote.RemoteState
import app.cadenza.remote.pairBluetooth
import app.cadenza.remote.showError

@Composable
fun PairingScreen(
    model: RemoteModel,
    state: RemoteState,
) {
    val context = LocalContext.current
    var name by rememberSaveable { mutableStateOf(state.clientName) }
    var pin by rememberSaveable { mutableStateOf("") }
    var scanning by rememberSaveable { mutableStateOf(false) }
    var pairingPending by rememberSaveable { mutableStateOf(false) }
    val cameraPermission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) {
                scanning = true
            } else {
                model.showError("Camera unavailable", "Allow camera access to scan the pairing QR code from Cadenza Host.")
            }
        }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier
                .widthIn(max = 720.dp)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 28.dp, vertical = 32.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            PairingHeader(state)
            if (pairingPending) PairingPendingSurface()
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.extraLarge,
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                tonalElevation = 2.dp,
            ) {
                Column(
                    Modifier.padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    Text("Connect this Remote", style = MaterialTheme.typography.titleLarge)
                    Text(
                        "Give this device a name, then enter the short PIN shown by Cadenza Host while both devices are nearby.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it.take(80) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("This Remote's name") },
                        isError = name.isBlank(),
                        supportingText = if (name.isBlank()) ({ Text("Enter a name before scanning.") }) else null,
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = pin,
                        onValueChange = { value -> pin = value.filter(Char::isDigit).take(4) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Host PIN") },
                        supportingText = { Text("The PIN expires after seven seconds.") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true,
                    )
                    Button(
                        onClick = { model.pairBluetooth(pin, name) },
                        enabled = !state.connecting && name.isNotBlank() && pin.length == 4,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(cadenzaVector(CadenzaIcon.QR), contentDescription = null)
                        Spacer(Modifier.size(10.dp))
                        Text(if (state.connecting) "Pairing..." else "Pair over Bluetooth")
                    }
                    Text(
                        "Bluetooth creates the first trusted connection. You can add LAN later for faster artwork and bulk transfers.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedButton(
                        onClick = {
                            if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                                PackageManager.PERMISSION_GRANTED
                            ) {
                                scanning = true
                            } else {
                                cameraPermission.launch(Manifest.permission.CAMERA)
                            }
                        },
                        enabled = !state.connecting && !pairingPending && name.isNotBlank(),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(cadenzaVector(CadenzaIcon.QR), contentDescription = null)
                        Spacer(Modifier.size(10.dp))
                        Text("Use pairing QR instead")
                    }
                    Text(
                        "Cadenza Host will send this Remote's name with the one-time invitation. Pairing starts as soon as the QR code is recognized.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Text(
                "Pairing stays on your local network. The invitation can only be used once.",
                modifier = Modifier.fillMaxWidth(),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    if (scanning) {
        Dialog(onDismissRequest = { scanning = false }) {
            Surface(
                shape = MaterialTheme.shapes.extraLarge,
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
            ) {
                Column(
                    Modifier.padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("Scan the Host QR code", style = MaterialTheme.typography.titleLarge)
                    Text(
                        "Keep the complete code inside the frame.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    QrScanner(
                        onCode = { code ->
                            scanning = false
                            pairingPending = true
                            model.pair(code, name)
                        },
                        onError = { message ->
                            scanning = false
                            pairingPending = false
                            model.showError("Could not scan QR", message)
                        },
                    )
                    TextButton(onClick = { scanning = false }, modifier = Modifier.align(Alignment.End)) { Text("Cancel") }
                }
            }
        }
    }
    LaunchedEffect(state.connected, state.connecting, state.connectionIssue, state.prompt?.id) {
        if (state.connected || (!state.connecting && state.connectionIssue != null)) pairingPending = false
    }
}

@Composable
private fun PairingPendingSurface() {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.primaryContainer,
    ) {
        Row(
            Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(28.dp),
                color = MaterialTheme.colorScheme.onPrimaryContainer,
                strokeWidth = 3.dp,
            )
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Pairing with Cadenza Host", color = MaterialTheme.colorScheme.onPrimaryContainer)
                Text(
                    "QR accepted. Connecting on your local network…",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }
        }
    }
}

@Composable
private fun PairingHeader(state: RemoteState) {
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Surface(
            Modifier.size(76.dp),
            shape = MaterialTheme.shapes.extraLarge,
            color = MaterialTheme.colorScheme.primaryContainer,
        ) {
            Box(
                Modifier.fillMaxSize().padding(18.dp),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    cadenzaVector(CadenzaIcon.QR),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    modifier = Modifier.size(40.dp),
                )
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text("Pair with Cadenza Host", style = MaterialTheme.typography.headlineMedium)
            Text(
                "Connect to the Mac that controls Music.",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            ConnectionStatus(state)
        }
    }
}
