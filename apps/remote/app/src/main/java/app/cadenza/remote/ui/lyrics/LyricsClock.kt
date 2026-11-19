package app.cadenza.remote.ui.lyrics

import android.os.SystemClock
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import app.cadenza.remote.data.LyricLine

/**
 * The lyric position sampled once per animation frame from the Host-synchronised playback timeline.
 * Only draw-phase code that calls [liveMs] observes it, so a frame invalidates drawing of the sweeping
 * word and finishing word rather than recomposing the list. Nothing here writes SQLite or sends a message.
 */
@Stable
internal class LyricsClock(
    private val positionAt: (elapsedRealtimeMs: Long) -> Long,
) {
    private var frameElapsedMs by mutableLongStateOf(SystemClock.elapsedRealtime())

    fun advanceFrame() {
        frameElapsedMs = SystemClock.elapsedRealtime()
    }

    /** Position at the last frame. Reading it in a draw or layout lambda subscribes that lambda to frames. */
    fun liveMs(): Long = positionAt(frameElapsedMs)
}

/**
 * Drives the word sweep. While [enabled], a frame loop advances [clock] and publishes the sweeping word.
 * The loop runs only while the host lifecycle is STARTED and the song plays; a paused view runs one frame per
 * [pausedPositionMs] change so a seek still repositions the fill. The published target changes only when the
 * sweeping word does, so composition runs once per word, not once per frame.
 */
@Composable
internal fun rememberSweepTarget(
    lines: List<LyricLine>,
    clock: LyricsClock,
    enabled: Boolean,
    playing: Boolean,
    pausedPositionMs: Long,
): State<SweepTarget?> {
    val target = remember { mutableStateOf<SweepTarget?>(null) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lines, clock, enabled, playing, if (playing) 0L else pausedPositionMs) {
        if (!enabled) {
            target.value = null
            return@LaunchedEffect
        }
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            do {
                withFrameNanos {
                    clock.advanceFrame()
                    target.value = sweepTarget(lines, clock.liveMs())
                }
            } while (playing)
        }
    }
    return target
}

/** True when the system animator scale is zero. Blur, scale, scroll and sweep animation then give way to instant state. */
@Composable
internal fun rememberReducedMotion(): Boolean {
    val resolver = LocalContext.current.contentResolver
    return remember(resolver) {
        Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}
