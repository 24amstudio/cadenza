package app.cadenza.remote.model

import android.os.SystemClock
import android.util.Base64
import androidx.lifecycle.viewModelScope
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.nullableString
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
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

// Entries are written to the local outbox off the main thread and then sent to the Host in batches. A burst of taps
// costs one frame, and the outbox keeps every entry until the Host accepts it.
internal fun RemoteModel.reportLog(
    level: String,
    action: String,
    message: String,
) {
    viewModelScope.launch(updateDispatcher) { updateApp.database.queueLog(level, action, message) }
    scheduleLogFlush()
}

// Records what the user did, so the Host's log shows the Remote's side of every request.
fun RemoteModel.recordUserAction(
    action: String,
    detail: String,
) = reportLog("info", action, detail)

internal fun RemoteModel.scheduleLogFlush() {
    if (logFlush?.isActive == true) return
    logFlush =
        viewModelScope.launch {
            delay(LOG_FLUSH_DELAY_MS)
            flushLogOutbox()
        }
}

internal suspend fun RemoteModel.reloadStatistics() {
    val host = mutableState.value.profile?.hostId ?: return
    val statistics = withContext(updateDispatcher) { updateApp.database.statistics(host) }
    mutableState.update { it.copy(statistics = statistics) }
}

fun RemoteModel.removeHistory(item: app.cadenza.remote.data.SongStatistic) {
    val host = mutableState.value.profile?.hostId ?: return
    viewModelScope.launch(updateDispatcher) {
        updateApp.database.removeStatistic(host, item.source, item.songId)
        reloadStatistics()
    }
}

internal fun RemoteModel.requestArtwork(url: String) {
    val state = mutableState.value
    if (!state.connected ||
        url.isBlank() || state.artwork.containsKey(url) || !reserveArtwork(url)
    ) {
        return
    }
    val sent = sendToHost(Wire.frame("artwork.get").put("request_id", nextRequestId()).put("artwork_url", url))
    if (!sent) releaseArtwork(url)
}

internal fun RemoteModel.applyArtworkFrame(frame: JSONObject) {
    val startedAt = SystemClock.elapsedRealtime()
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
            recordComponentDuration(
                "artwork",
                (SystemClock.elapsedRealtime() - startedAt).coerceAtLeast(0),
                "bytes=${bytes.size}",
            )
        }
}

// Sends the outbox in batches of up to 100 entries. A batch is deleted only after its send succeeds, so a dropped
// connection never loses entries.
internal suspend fun RemoteModel.flushLogOutbox() {
    if (!mutableState.value.connected) return
    while (true) {
        val batch = withContext(updateDispatcher) { updateApp.database.pendingLogs() }
        if (batch.isEmpty()) return
        val entries = JSONArray()
        for (entry in batch) {
            entries.put(JSONObject().put("level", entry.level).put("action", entry.action).put("message", entry.message))
        }
        if (!sendToHost(Wire.frame("log.report").put("log_entries", entries))) return
        withContext(updateDispatcher) { updateApp.database.deleteLogs(batch.map { it.id }) }
    }
}

private const val LOG_FLUSH_DELAY_MS = 1_000L
