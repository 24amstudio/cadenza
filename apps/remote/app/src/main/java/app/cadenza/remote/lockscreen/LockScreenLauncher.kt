package app.cadenza.remote.lockscreen

import android.content.Context
import android.content.Intent
import app.cadenza.remote.device.DeviceState
import app.cadenza.remote.playback.NowPlayingHub
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

/** Opens the motion lock screen when the screen turns off during playback that has a motion clip ready. */
class LockScreenLauncher(
    private val context: Context,
    private val device: DeviceState,
    private val scope: CoroutineScope,
) {
    fun start() {
        scope.launch {
            device.screenInteractive.drop(1).collect { interactive ->
                if (interactive) return@collect
                val snapshot = NowPlayingHub.snapshot.value ?: return@collect
                if (!LockScreenPolicy.shouldOpen(
                        motionEnabled = snapshot.motionEnabled,
                        hasMotionArtwork = snapshot.motion != null,
                        playing = snapshot.playing,
                        connected = snapshot.connected,
                        screenOff = true,
                    )
                ) {
                    return@collect
                }
                runCatching {
                    context.startActivity(
                        Intent(context, LockScreenNowPlayingActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                }
            }
        }
    }
}
