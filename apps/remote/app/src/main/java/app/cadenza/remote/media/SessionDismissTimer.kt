package app.cadenza.remote.media

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** How long a paused or disconnected session keeps its notification before the notification is dismissed. */
internal const val SESSION_DISMISS_AFTER_MS = 5 * 60_000L

/**
 * Dismisses the session notification once Host has stayed paused or disconnected for [afterMs]. One wait starts when the
 * session stops, and playing again cancels it. Nothing waits while the session is live.
 */
internal class SessionDismissTimer(
    private val scope: CoroutineScope,
    private val afterMs: Long = SESSION_DISMISS_AFTER_MS,
    private val onDismiss: () -> Unit,
) {
    private var pending: Job? = null

    fun track(live: Boolean) {
        if (live) {
            pending?.cancel()
            pending = null
            return
        }
        if (pending == null) {
            pending =
                scope.launch {
                    delay(afterMs)
                    onDismiss()
                }
        }
    }
}
