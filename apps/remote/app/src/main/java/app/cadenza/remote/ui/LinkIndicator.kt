package app.cadenza.remote.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.ui.lyrics.rememberReducedMotion
import kotlinx.coroutines.delay

private const val FLASH_MS = 320

/**
 * Connection quality and traffic beside the now playing text: the transport that carries the link, signal bars, then a
 * down arrow for frames received and an up arrow for frames sent.
 */
@Composable
fun LiveLinkIndicator(
    model: RemoteModel,
    state: RemoteState,
    modifier: Modifier = Modifier,
) {
    val incoming by model.traffic.incoming.collectAsStateWithLifecycle()
    val outgoing by model.traffic.outgoing.collectAsStateWithLifecycle()
    LinkIndicator(
        bars = linkSignalBars(state.connected, state.linkRoundTripMs),
        transport = linkTransportOf(state.transportMode, state.effectiveTransport?.selected).takeIf { state.connected },
        incoming = incoming,
        outgoing = outgoing,
        modifier = modifier,
    )
}

@Composable
internal fun LinkIndicator(
    bars: Int,
    transport: LinkTransport?,
    incoming: Long,
    outgoing: Long,
    modifier: Modifier = Modifier,
) {
    val carrier =
        when (transport) {
            LinkTransport.BLUETOOTH -> "Bluetooth"
            LinkTransport.WIFI -> "Wi-Fi"
            null -> null
        }
    val description =
        when {
            bars == 0 -> "Not connected to Cadenza Host"
            carrier == null -> "Signal $bars of $SIGNAL_BAR_COUNT bars"
            else -> "$carrier signal $bars of $SIGNAL_BAR_COUNT bars"
        }
    Row(
        modifier.semantics(mergeDescendants = true) { contentDescription = description },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (transport != null) TransportGlyph(transport)
        SignalBars(bars)
        FlashArrow(down = true, pulse = incoming)
        FlashArrow(down = false, pulse = outgoing)
    }
}

@Composable
private fun TransportGlyph(transport: LinkTransport) {
    Icon(
        cadenzaVector(if (transport == LinkTransport.BLUETOOTH) CadenzaIcon.BLUETOOTH else CadenzaIcon.WIFI),
        contentDescription = null,
        tint = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.size(14.dp),
    )
}

@Composable
private fun SignalBars(bars: Int) {
    val lit = MaterialTheme.colorScheme.onSurface
    val dim = MaterialTheme.colorScheme.outlineVariant
    Canvas(Modifier.size(width = 16.dp, height = 12.dp)) {
        val gap = 2.dp.toPx()
        val width = (size.width - gap * (SIGNAL_BAR_COUNT - 1)) / SIGNAL_BAR_COUNT
        for (index in 0 until SIGNAL_BAR_COUNT) {
            val height = size.height * (index + 1) / SIGNAL_BAR_COUNT
            drawRect(
                color = if (index < bars) lit else dim,
                topLeft = Offset(index * (width + gap), size.height - height),
                size = Size(width, height),
            )
        }
    }
}

// Each new pulse restarts the flash, so a burst of frames flashes once per pulse. Reduced motion holds the colour
// for the same time without a fade.
@Composable
private fun FlashArrow(
    down: Boolean,
    pulse: Long,
) {
    val rest = MaterialTheme.colorScheme.onSurfaceVariant
    val lit = MaterialTheme.colorScheme.primary
    val reduced = rememberReducedMotion()
    // 0 is the flash colour and 1 the resting colour, so the blend stays in the theme's own colours.
    val fade = remember { Animatable(1f) }
    LaunchedEffect(pulse) {
        if (pulse == 0L) return@LaunchedEffect
        fade.snapTo(0f)
        if (reduced) {
            delay(FLASH_MS.toLong())
            fade.snapTo(1f)
        } else {
            fade.animateTo(1f, tween(FLASH_MS))
        }
    }
    Canvas(Modifier.size(10.dp)) {
        val color = lerp(lit, rest, fade.value)
        val stroke = Stroke(width = 1.6.dp.toPx(), cap = StrokeCap.Round)
        val w = size.width
        val h = size.height
        val path =
            Path().apply {
                if (down) {
                    moveTo(w / 2, 0f)
                    lineTo(w / 2, h)
                    moveTo(w * 0.2f, h * 0.65f)
                    lineTo(w / 2, h)
                    lineTo(w * 0.8f, h * 0.65f)
                } else {
                    moveTo(w / 2, h)
                    lineTo(w / 2, 0f)
                    moveTo(w * 0.2f, h * 0.35f)
                    lineTo(w / 2, 0f)
                    lineTo(w * 0.8f, h * 0.35f)
                }
            }
        drawPath(path, color = color, style = stroke)
    }
}
