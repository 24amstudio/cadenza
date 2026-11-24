package app.cadenza.remote.model

import androidx.lifecycle.viewModelScope
import app.cadenza.remote.media.SessionDismissTimer
import app.cadenza.remote.media.SessionNotification
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** Starts the watch that clears the session notification once a pause or a lost connection lasts several minutes. */
internal fun RemoteModel.startSessionDismissal() {
    val timer = SessionDismissTimer(viewModelScope) { SessionNotification(app).clear() }
    viewModelScope.launch {
        state
            .map { it.connected && it.snapshot?.playing == true }
            .distinctUntilChanged()
            .collect { live -> timer.track(live) }
    }
}
