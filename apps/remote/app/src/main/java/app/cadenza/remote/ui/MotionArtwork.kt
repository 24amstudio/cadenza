package app.cadenza.remote.ui

import android.net.Uri
import android.provider.Settings
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import java.io.File

// Album motion loops silently in the cover slot. It plays only while this screen is resumed and the Host is playing.
// The still cover stays underneath and fades out only once the first video frame is on screen, so the switch never
// flashes black. Reduced motion keeps the still cover. The Host sends the square rendition, so the default fit fills the slot.
@Composable
fun MotionArtwork(
    video: File?,
    playing: Boolean,
    modifier: Modifier = Modifier,
    fallback: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val reducedMotion =
        remember(context) {
            Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        }
    if (video == null || reducedMotion) {
        Box(modifier) { fallback() }
        return
    }
    val player =
        remember(video) {
            ExoPlayer.Builder(context).build().apply {
                setMediaItem(MediaItem.fromUri(Uri.fromFile(video)))
                repeatMode = Player.REPEAT_MODE_ONE
                volume = 0f
                prepare()
            }
        }
    var rendered by remember(video) { mutableStateOf(false) }
    DisposableEffect(player) {
        val listener =
            object : Player.Listener {
                override fun onRenderedFirstFrame() {
                    rendered = true
                }
            }
        player.addListener(listener)
        onDispose {
            player.removeListener(listener)
            player.release()
        }
    }
    LifecycleResumeEffect(player, playing) {
        player.playWhenReady = playing
        onPauseOrDispose { player.playWhenReady = false }
    }
    Box(modifier) {
        fallback()
        AnimatedVisibility(visible = rendered, enter = fadeIn(), exit = fadeOut()) {
            AndroidView(
                factory = { viewContext ->
                    PlayerView(viewContext).apply {
                        useController = false
                        this.player = player
                    }
                },
                update = { it.player = player },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}
