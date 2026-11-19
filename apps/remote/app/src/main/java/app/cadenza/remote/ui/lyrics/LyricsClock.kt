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
import kotlinx.coroutines.delay

/**
 * The lyric position sampled once per animation frame from the Host-synchronised playback timeline.
 * Only draw-phase code that calls [liveMs] observes it, so a frame invalidates drawing of the sounding
 * words rather than recomposing the list. Nothing here writes SQLite or sends a message.
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
 * Drives the word sweep. While [enabled], a frame loop at most [frameCapFps] times a second advances [clock] and
 * publishes every sounding word.
 * The loop runs only while the host lifecycle is STARTED and the song plays; a paused view runs one frame per
 * [pausedPositionMs] change so a seek still repositions the fill. The published sweeps change only when a word
 * starts or stops sounding, so composition runs once per word boundary, not once per frame.
 */
@Composable
internal fun rememberSweeps(
    lines: List<LyricLine>,
    clock: LyricsClock,
    enabled: Boolean,
    playing: Boolean,
    pausedPositionMs: Long,
    frameCapFps: Int = DEFAULT_FRAME_CAP_FPS,
): State<Sweeps> {
    val target = remember { mutableStateOf<Sweeps>(emptyMap()) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lines, clock, enabled, playing, frameCapFps, if (playing) 0L else pausedPositionMs) {
        if (!enabled) {
            target.value = emptyMap()
            return@LaunchedEffect
        }
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            do {
                withFrameNanos {
                    clock.advanceFrame()
                    target.value = sweepTargets(lines, clock.liveMs())
                }
                // Sleeping until half a frame before the next sample keeps the loop from waking on every vsync of a
                // 90 or 120 Hz display. The frame cap is the energy profile's lyric animation rate.
                if (playing) delay(frameGapMs(frameCapFps))
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

internal const val DEFAULT_FRAME_CAP_FPS = 60
private const val HALF_FRAME_LEAD_MS = 8L

/** Time to sleep after a frame so the next sample lands near one cap interval later. Never negative. */
internal fun frameGapMs(capFps: Int): Long = (1_000L / capFps.coerceAtLeast(1) - HALF_FRAME_LEAD_MS).coerceAtLeast(0)
