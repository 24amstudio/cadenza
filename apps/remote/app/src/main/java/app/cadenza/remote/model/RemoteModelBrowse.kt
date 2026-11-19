package app.cadenza.remote.model

import android.os.SystemClock
import androidx.lifecycle.viewModelScope
import app.cadenza.remote.data.BrowsePage
import app.cadenza.remote.data.BrowseTarget
import app.cadenza.remote.data.BrowseWire
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.nullableString
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.json.JSONObject

sealed interface BrowseLoad {
    data object Loading : BrowseLoad

    data class Ready(
        val page: BrowsePage,
        val loadedAtElapsedMs: Long,
    ) : BrowseLoad

    data class Failed(
        val message: String,
    ) : BrowseLoad
}

private const val BROWSE_TIMEOUT_MS = 20_000L
private const val CACHED_PAGES = 12
private const val PLAYLIST_FRESH_MS = 60_000L
private const val CATALOG_FRESH_MS = 300_000L

internal fun BrowseTarget.freshForMs(): Long = if (kind == "playlists" || kind == "playlist") PLAYLIST_FRESH_MS else CATALOG_FRESH_MS

// Pages stay in memory briefly, so rotating the screen or stepping back to a page shows it at once. The Host keeps its
// own cache, so an expired page here is one cheap request.
fun RemoteModel.browse(
    target: BrowseTarget,
    refresh: Boolean = false,
) {
    val key = target.key
    val existing = mutable.value.browse[key]
    val now = SystemClock.elapsedRealtime()
    if (existing is BrowseLoad.Loading && !refresh) return
    if (existing is BrowseLoad.Ready && !refresh && now - existing.loadedAtElapsedMs < target.freshForMs()) return
    if (!mutable.value.connected || "library.browse" !in mutable.value.capabilities) {
        setBrowse(key, BrowseLoad.Failed("Reconnect to Cadenza Host to browse."))
        return
    }
    val requestId = id()
    browseRequests[requestId] = key
    setBrowse(key, BrowseLoad.Loading)
    reportLog("info", "browse.requested", "kind=${target.kind}")
    connection?.send(Wire.frame("browse.get").put("request_id", requestId).put("browse", target.request()))
    browseTimeouts[requestId] =
        viewModelScope.launch {
            delay(BROWSE_TIMEOUT_MS)
            if (browseRequests[requestId] == key && mutable.value.browse[key] is BrowseLoad.Loading) {
                browseRequests.remove(requestId)
                setBrowse(key, BrowseLoad.Failed("Cadenza Host did not answer. Try again."))
            }
        }
}

// Leaving a page that is still loading stops the Host's work for it.
fun RemoteModel.cancelBrowse(target: BrowseTarget) {
    val key = target.key
    if (mutable.value.browse[key] !is BrowseLoad.Loading) return
    for ((requestId, requested) in browseRequests.entries.toList()) {
        if (requested != key) continue
        browseRequests.remove(requestId)
        browseTimeouts.remove(requestId)?.cancel()
        connection?.send(Wire.frame("operation.cancel").put("request_id", requestId))
    }
    mutable.update { it.copy(browse = it.browse - key) }
}

internal fun RemoteModel.applyBrowseResult(frame: JSONObject) {
    val requestId = frame.nullableString("request_id") ?: return
    val key = browseRequests.remove(requestId) ?: return
    browseTimeouts.remove(requestId)?.cancel()
    val page =
        try {
            BrowseWire.page(frame)
        } catch (error: Exception) {
            setBrowse(key, BrowseLoad.Failed(error.message ?: "Cadenza Host sent a page this Remote cannot show."))
            return
        }
    setBrowse(key, BrowseLoad.Ready(page, SystemClock.elapsedRealtime()))
}

// A failed browse request shows inside its page, where the user is looking, instead of as a separate toast.
internal fun RemoteModel.applyBrowseError(frame: JSONObject): Boolean {
    val requestId = frame.nullableString("request_id") ?: return false
    val key = browseRequests.remove(requestId) ?: return false
    browseTimeouts.remove(requestId)?.cancel()
    val message =
        when (frame.nullableString("error_code")) {
            "not_found" -> "Music has nothing to show for this."
            "catalog_unavailable" -> "Apple Music is not reachable from Cadenza Host right now."
            else -> frame.optString("message", "This page could not be loaded.")
        }
    setBrowse(key, BrowseLoad.Failed(message))
    return true
}

private fun RemoteModel.setBrowse(
    key: String,
    load: BrowseLoad,
) {
    mutable.update { state ->
        val next = LinkedHashMap(state.browse)
        next.remove(key)
        next[key] = load
        while (next.size > CACHED_PAGES) next.remove(next.keys.first())
        state.copy(browse = next)
    }
}
