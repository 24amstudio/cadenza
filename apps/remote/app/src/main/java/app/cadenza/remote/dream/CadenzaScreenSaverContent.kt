package app.cadenza.remote.dream

import android.graphics.BitmapFactory
import android.os.SystemClock
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.cadenza.remote.playback.NowPlayingSnapshot
import kotlinx.coroutines.delay

private const val DRIFT_HALF_CYCLE_MS = 22_500
private const val DRIFT_DISTANCE_DP = 24f
private val nightStroke = Color(0xFF8E8E93)

/**
 * The three burn-in stages. The stage changes at two fixed idle thresholds, so the scene waits for each one instead of
 * running a frame timer. Drift is the only animation, and it moves the text slowly so no pixel stays lit.
 */
@Composable
fun CadenzaScreenSaverContent(
    snapshot: NowPlayingSnapshot?,
    lyricIndex: Int?,
) {
    MaterialExpressiveTheme(colorScheme = darkColorScheme()) {
        var stage by remember { mutableStateOf(DreamStage.AMBIENT) }
        LaunchedEffect(Unit) {
            delay(DRIFT_STARTS_MS)
            stage = DreamStage.DRIFT
            delay(NIGHT_STARTS_MS - DRIFT_STARTS_MS)
            stage = DreamStage.NIGHT
        }
        val artwork = remember(snapshot?.artwork) { snapshot?.artwork?.let(::decodeArtwork) }
        val line =
            lyricIndex
                ?.let {
                    snapshot
                        ?.lyrics
                        ?.lines
                        ?.getOrNull(it)
                        ?.text
                }.orEmpty()
        val drift by rememberInfiniteTransition(label = "drift").animateFloat(
            initialValue = -1f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(DRIFT_HALF_CYCLE_MS, easing = LinearEasing), RepeatMode.Reverse),
            label = "drift-offset",
        )
        val offset = if (stage == DreamStage.DRIFT) (DRIFT_DISTANCE_DP * drift).dp else 0.dp

        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (stage != DreamStage.NIGHT && artwork != null) {
                Image(
                    bitmap = artwork,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier =
                        Modifier
                            .fillMaxSize()
                            .blur(ARTWORK_BLUR_DP.dp)
                            .alpha(if (stage == DreamStage.AMBIENT) AMBIENT_ALPHA else DRIFT_ALPHA),
                )
            }
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Brush.radialGradient(listOf(Color.Transparent, Color.Black))),
            )
            Column(
                Modifier
                    .align(Alignment.Center)
                    .fillMaxWidth()
                    .offset(x = offset, y = offset)
                    .padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                val textColor = if (stage == DreamStage.NIGHT) nightStroke else Color.White
                val weight = if (stage == DreamStage.NIGHT) FontWeight.Light else FontWeight.SemiBold
                Text(
                    snapshot?.title.orEmpty(),
                    color = textColor,
                    fontWeight = weight,
                    style = MaterialTheme.typography.displaySmall,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    snapshot?.artist.orEmpty(),
                    color = textColor,
                    fontWeight = FontWeight.Light,
                    style = MaterialTheme.typography.titleLarge,
                    textAlign = TextAlign.Center,
                )
                if (stage == DreamStage.AMBIENT && line.isNotBlank()) {
                    Text(
                        line,
                        color = Color.White,
                        style = MaterialTheme.typography.headlineSmall,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 24.dp),
                    )
                }
                if (stage == DreamStage.NIGHT) {
                    Text(
                        elapsedText(snapshot),
                        color = nightStroke,
                        fontWeight = FontWeight.Light,
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.padding(top = 24.dp),
                    )
                }
            }
        }
    }
}

private fun decodeArtwork(bytes: ByteArray) = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()

private fun elapsedText(snapshot: NowPlayingSnapshot?): String {
    val totalSeconds = (snapshot?.positionAt(SystemClock.elapsedRealtime()) ?: 0L).coerceAtLeast(0) / 1_000
    return "%d:%02d".format(totalSeconds / 60, totalSeconds % 60)
}

private const val ARTWORK_BLUR_DP = 48
private const val AMBIENT_ALPHA = 0.16f
private const val DRIFT_ALPHA = 0.08f
