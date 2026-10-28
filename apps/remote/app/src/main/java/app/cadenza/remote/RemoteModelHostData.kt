package app.cadenza.remote

import android.util.Base64
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.nullableString
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import org.json.JSONObject

internal fun RemoteModel.sendToHost(frame: JSONObject): Boolean = connection?.send(frame) == true

internal fun RemoteModel.nextRequestId(): String = id()

internal fun RemoteModel.reserveArtwork(url: String): Boolean = artworkRequests.add(url)

internal fun RemoteModel.releaseArtwork(url: String) {
    artworkRequests.remove(url)
}

internal fun RemoteModel.clearArtworkRequests() {
    artworkRequests.clear()
}

internal fun RemoteModel.reportLog(
    level: String,
    action: String,
    message: String,
) {
    updateApp.database.queueLog(level, action, message)
    flushLogOutbox()
}

internal suspend fun RemoteModel.reloadStatistics() {
    val host = mutableState.value.profile?.hostId ?: return
    val statistics = withContext(updateDispatcher) { updateApp.database.statistics(host) }
    mutableState.update { it.copy(statistics = statistics) }
}

internal fun RemoteModel.requestArtwork(url: String) {
    val state = mutableState.value
    if (!state.connected || "artwork.host-cache" !in state.capabilities ||
        url.isBlank() || state.artwork.containsKey(url) || !reserveArtwork(url)
    ) {
        return
    }
    val sent = sendToHost(Wire.frame("artwork.get").put("request_id", nextRequestId()).put("artwork_url", url))
    if (!sent) releaseArtwork(url)
}

internal fun RemoteModel.applyArtworkFrame(frame: JSONObject) {
    val url = frame.nullableString("artwork_url")
    val encoded = frame.nullableString("artwork_data_base64")
    if (url == null || encoded == null || encoded.length > 700_000) return
    runCatching { Base64.decode(encoded, Base64.DEFAULT) }
        .getOrNull()
        ?.takeIf { it.size <= 524_288 }
        ?.let { bytes ->
            releaseArtwork(url)
            mutableState.update { current ->
                val next = LinkedHashMap(current.artwork)
                if (!next.containsKey(url) && next.size >= 8) next.remove(next.keys.first())
                next[url] = bytes
                current.copy(artwork = next)
            }
        }
}

internal fun RemoteModel.flushLogOutbox() {
    if (!mutableState.value.connected) return
    for (entry in updateApp.database.pendingLogs()) {
        val frame =
            Wire
                .frame("log.report")
                .put("log_level", entry.level)
                .put("log_action", entry.action)
                .put("log_message", entry.message)
        if (sendToHost(frame)) updateApp.database.deleteLog(entry.id) else return
    }
}
