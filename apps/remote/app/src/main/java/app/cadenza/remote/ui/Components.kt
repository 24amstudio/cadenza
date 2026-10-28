package app.cadenza.remote.ui

import android.os.SystemClock
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import app.cadenza.remote.RemoteModel
import app.cadenza.remote.RemoteState
import kotlinx.coroutines.delay

@Composable
fun LoadingScreen(label: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
            CircularProgressIndicator()
            Text(label)
        }
    }
}

@Composable
fun ActionButton(
    label: String,
    modifier: Modifier = Modifier,
    pending: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Button(onClick = onClick, enabled = enabled && !pending, modifier = modifier) {
        if (pending) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            Spacer(Modifier.size(8.dp))
        }
        Text(if (pending) "Working…" else label)
    }
}

@Composable
fun ConnectionStatus(state: RemoteState) {
    if (state.connecting) {
        Icon(
            cadenzaVector(CadenzaIcon.WIFI_OFF),
            contentDescription = "Reconnecting to " + (state.profile?.name ?: "Host"),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(24.dp).semantics { liveRegion = LiveRegionMode.Polite },
        )
    } else {
        val label = if (state.connected) state.profile?.name ?: "Connected" else state.connectionIssue ?: "Disconnected"
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
        )
    }
}

@Composable
fun KeepScreenAwake(enabled: Boolean) {
    val view = LocalView.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(view, lifecycle, enabled) {
        val observer =
            LifecycleEventObserver { _, event ->
                when (event) {
                    Lifecycle.Event.ON_START -> view.keepScreenOn = enabled
                    Lifecycle.Event.ON_STOP -> view.keepScreenOn = false
                    else -> Unit
                }
            }
        lifecycle.addObserver(observer)
        view.keepScreenOn = enabled && lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
        onDispose {
            lifecycle.removeObserver(observer)
            view.keepScreenOn = false
        }
    }
}

@Composable
fun position(
    model: RemoteModel,
    interval: Long = 200,
    advance: Boolean =
        model.state.value.connected && model.state.value.snapshot
            ?.playing == true,
): Long {
    var now by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(model, interval, lifecycle, advance) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (advance) {
                now = SystemClock.elapsedRealtime()
                delay(interval)
            }
        }
    }
    return model.position(now)
}

fun duration(milliseconds: Long?): String {
    if (milliseconds == null) return "Unknown"
    val seconds = milliseconds.coerceAtLeast(0) / 1_000
    return if (seconds >= 3_600) {
        (seconds / 3_600).toString() + ":" + (seconds / 60 % 60).toString().padStart(2, '0') + ":" +
            (seconds % 60).toString().padStart(2, '0')
    } else {
        (seconds / 60).toString() + ":" + (seconds % 60).toString().padStart(2, '0')
    }
}

@Composable
fun Artwork(
    url: String?,
    modifier: Modifier = Modifier,
) {
    Artwork(rememberArtwork(url), modifier)
}

@Composable
internal fun Artwork(
    artwork: ArtworkData?,
    modifier: Modifier,
) {
    Surface(modifier = modifier, shape = RoundedCornerShape(28.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
        Box(contentAlignment = Alignment.Center) {
            val bitmap = artwork?.image
            if (bitmap !=
                null
            ) {
                Image(bitmap, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            } else {
                Box(
                    Modifier.fillMaxSize().background(
                        Brush.linearGradient(
                            listOf(MaterialTheme.colorScheme.primaryContainer, MaterialTheme.colorScheme.tertiaryContainer),
                        ),
                    ),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        cadenzaVector(CadenzaIcon.MUSIC),
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                        modifier = Modifier.size(56.dp),
                    )
                }
            }
        }
    }
}

@Composable
fun ScreenHeader(
    title: String,
    state: RemoteState,
) {
    Column(Modifier.fillMaxWidth().padding(bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.headlineLarge)
        ConnectionStatus(state)
    }
}
