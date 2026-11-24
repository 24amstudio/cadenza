package app.cadenza.remote.widget

import android.content.Context
import android.os.SystemClock
import app.cadenza.remote.device.DeviceState
import app.cadenza.remote.media.LyricBoundaryTicker
import app.cadenza.remote.playback.NowPlayingHub
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * Connects the shared now-playing state to the widget. It wakes on track and play changes, on lyric boundaries, and on
 * screen and unlock events. Nothing here runs on a fixed interval.
 */
class WidgetObserver(
    private val context: Context,
    private val device: DeviceState,
    private val scope: CoroutineScope,
) {
    fun start() {
        val ticker = LyricBoundaryTicker(scope, SystemClock::elapsedRealtime, WidgetRenderer::publishLyricIndex)
        scope.launch { NowPlayingHub.snapshot.collect(ticker::follow) }
        scope.launch {
            combine(NowPlayingHub.snapshot, WidgetRenderer.lyricIndex, device.screenInteractive) { snapshot, index, interactive ->
                Triple(snapshot, index, interactive)
            }.collect { (snapshot, index, interactive) ->
                WidgetRenderer.render(context, snapshot, index, interactive)
            }
        }
        scope.launch {
            device.userPresent.collect {
                // The first render after unlock is a full one, so the lock screen's stale lyric is replaced at once.
                WidgetRenderer.invalidate()
                WidgetRenderer.render(
                    context,
                    NowPlayingHub.snapshot.value,
                    WidgetRenderer.lyricIndex.value,
                    device.screenInteractive.value,
                )
            }
        }
    }
}
