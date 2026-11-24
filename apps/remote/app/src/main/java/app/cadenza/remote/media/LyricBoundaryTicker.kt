package app.cadenza.remote.media

import app.cadenza.remote.playback.NowPlayingSnapshot
import app.cadenza.remote.ui.lyrics.activeLineIndices
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Reports the active timed lyric line. While the Host plays it sleeps until the next line starts or ends, so a surface
 * that shows the line needs no periodic timer. Paused playback reports once and does not wait.
 */
internal class LyricBoundaryTicker(
    private val scope: CoroutineScope,
    private val elapsedMs: () -> Long,
    private val report: (Int?) -> Unit,
) {
    private var job: Job? = null

    fun follow(snapshot: NowPlayingSnapshot?) {
        job?.cancel()
        job = null
        val lines = snapshot?.lyrics?.lines
        if (snapshot == null || lines == null) {
            report(null)
            return
        }
        job =
            scope.launch {
                do {
                    val position = snapshot.positionAt(elapsedMs())
                    report(activeLineIndices(lines, position).firstOrNull())
                    if (!snapshot.playing) return@launch
                    val next = nextLyricChangeMs(lines, position) ?: return@launch
                    delay((next - position).coerceAtLeast(1))
                } while (true)
            }
    }

    fun cancel() {
        job?.cancel()
        job = null
    }
}
