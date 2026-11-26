package app.cadenza.remote.dream

import android.graphics.Color
import android.os.SystemClock
import android.service.dreams.DreamService
import android.view.ViewGroup
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.core.graphics.drawable.toDrawable
import app.cadenza.remote.CadenzaApplication
import app.cadenza.remote.device.DeviceState
import app.cadenza.remote.playback.NowPlayingHub
import app.cadenza.remote.widget.WidgetRenderer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * The system screen saver. It stays up only while this Remote charges and the Host plays. The window is black before
 * Compose mounts, and finish() is always used, never wakeUp(), so the display turns off naturally when the gate closes.
 */
class CadenzaDreamService : DreamService() {
    private val eligibility = DreamActivationEligibility()
    private var lifecycle: DreamLifecycleOwner? = null
    private var scope: CoroutineScope? = null

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        isInteractive = true
        isFullscreen = true
        window?.setBackgroundDrawable(Color.BLACK.toDrawable())
    }

    override fun onDreamingStarted() {
        super.onDreamingStarted()
        val device = (application as CadenzaApplication).device
        if (!eligibility.canActivate(conditions(device), SystemClock.elapsedRealtime())) {
            finish()
            return
        }
        val owner = DreamLifecycleOwner()
        window?.decorView?.let(owner::attachTo)
        owner.resume()
        lifecycle = owner
        setContentView(
            ComposeView(this).apply {
                layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
                setContent { ScreenSaverScene() }
            },
        )
        val watch = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        scope = watch
        watch.launch {
            combine(NowPlayingHub.snapshot, device.charging) { _, _ -> conditions(device) }.collectLatest { current ->
                if (!eligibility.canActivate(current, SystemClock.elapsedRealtime())) {
                    finish()
                    return@collectLatest
                }
                if (!current.hostPlaying) {
                    // The grace has to run out on its own, because no new state arrives while the Host stays paused.
                    delay(DreamActivationEligibility.TRANSITION_GRACE_MS + 1)
                    if (!eligibility.canActivate(current, SystemClock.elapsedRealtime())) finish()
                }
            }
        }
    }

    override fun onDreamingStopped() {
        scope?.cancel()
        scope = null
        lifecycle?.destroy()
        lifecycle = null
        super.onDreamingStopped()
    }

    private fun conditions(device: DeviceState): DreamConditions {
        val snapshot = NowPlayingHub.snapshot.value
        return DreamConditions(
            hostConnected = snapshot?.connected == true,
            hostPlaying = snapshot?.playing == true,
            hasCurrentSong = snapshot?.hasCurrentSong == true,
            charging = device.charging.value,
        )
    }

    @Composable
    private fun ScreenSaverScene() {
        val snapshot by NowPlayingHub.snapshot.collectAsState()
        val lyricIndex by WidgetRenderer.lyricIndex.collectAsState()
        CadenzaScreenSaverContent(snapshot = snapshot, lyricIndex = lyricIndex)
    }
}
