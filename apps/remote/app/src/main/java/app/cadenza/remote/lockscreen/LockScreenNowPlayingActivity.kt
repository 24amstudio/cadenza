package app.cadenza.remote.lockscreen

import android.app.KeyguardManager
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import app.cadenza.remote.CadenzaApplication
import app.cadenza.remote.MainActivity
import app.cadenza.remote.media.PlaybackMediaService
import app.cadenza.remote.playback.NowPlayingHub
import app.cadenza.remote.widget.WidgetRenderer
import kotlinx.coroutines.launch

/**
 * Full-bleed motion artwork over the keyguard, for a playing track with motion artwork. It needs no overlay permission,
 * because it is an Activity shown with setShowWhenLocked. It closes on unlock, pause, or a lost Host.
 */
class LockScreenNowPlayingActivity : ComponentActivity() {
    private val device by lazy { (application as CadenzaApplication).device }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setShowWhenLocked(true)
        lifecycleScope.launch {
            NowPlayingHub.snapshot.collect { snapshot ->
                val playing = snapshot?.playing == true
                window.keepScreenOn(playing)
                if (LockScreenPolicy.shouldClose(playing, snapshot?.connected == true, userPresent = false)) {
                    finishAndRemoveTask()
                }
            }
        }
        lifecycleScope.launch {
            device.userPresent.collect { finishAndRemoveTask() }
        }
        setContent {
            val snapshot by NowPlayingHub.snapshot.collectAsState()
            val lyricIndex by WidgetRenderer.lyricIndex.collectAsState()
            LockScreenNowPlayingScreen(
                snapshot = snapshot,
                lyricIndex = lyricIndex,
                onControl = ::sendControl,
                onArtistTap = ::openAfterUnlock,
            )
        }
    }

    private fun sendControl(action: String) {
        ContextCompat.startForegroundService(
            this,
            Intent(this, PlaybackMediaService::class.java).putExtra(PlaybackMediaService.EXTRA_TRANSPORT, action),
        )
    }

    /** Opening the app while locked needs the keyguard dismissed first, so the user confirms the unlock. */
    private fun openAfterUnlock() {
        val keyguard = getSystemService(KeyguardManager::class.java)
        keyguard.requestDismissKeyguard(
            this,
            object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() {
                    startActivity(Intent(this@LockScreenNowPlayingActivity, MainActivity::class.java))
                }
            },
        )
    }

    private fun android.view.Window.keepScreenOn(on: Boolean) {
        if (on) addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) else clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
