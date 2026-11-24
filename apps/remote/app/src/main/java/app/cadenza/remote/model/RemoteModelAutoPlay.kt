package app.cadenza.remote.model

import androidx.lifecycle.viewModelScope
import app.cadenza.remote.data.AutoPlayItem
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.Wire
import app.cadenza.remote.search.normalizeSearchText
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.json.JSONObject

private const val AUTO_PLAY_TIMEOUT_MS = 25_000L

/** An AutoPlay song the user asked for while Cadenza finds its catalog recording and prepares it. */
data class AutoPlayRequest(
    val item: AutoPlayItem,
    val next: Boolean,
    val song: Song? = null,
)

/**
 * AutoPlay songs have no catalog identity in Music's queue, so a request finds the catalog recording with the same
 * title and artist. A version suffix such as "(Remastered 2014)" names the same recording.
 */
internal fun AutoPlayItem.matches(song: Song): Boolean =
    baseTitle(title) == baseTitle(song.title) && normalizeSearchText(artist) == normalizeSearchText(song.artist)

internal fun baseTitle(value: String): String = normalizeSearchText(value.replace(Regex("\\s*\\([^)]*\\)"), ""))

/** Whether the current song may be interrupted by this Remote, as the song sheet decides for its own requests. */
internal fun RemoteState.mayInterruptCurrent(): Boolean {
    val current = snapshot?.current
    return current == null || current.requestedBy == profile?.remoteId ||
        (snapshot.allowCrossRemoteEdits && current.requestedBy != null)
}

/** Whether an AutoPlay song can be requested now. Play now may interrupt the current song, and play next needs the capability. */
internal fun RemoteState.canRequestAutoPlay(next: Boolean): Boolean {
    if (!connected || snapshot?.synchronized != true || preparing || autoPlayRequest != null) return false
    if (next) return "queue.play-next" in capabilities
    return mayInterruptCurrent()
}

/** Starts a request: the catalog search runs on its own request id, so the search screen and its history stay as they are. */
internal fun RemoteModel.playAutoPlay(
    item: AutoPlayItem,
    next: Boolean,
) {
    if (!mutable.value.canRequestAutoPlay(next)) return
    val requestId = id()
    autoPlayId = requestId
    mutable.update { it.copy(autoPlayRequest = AutoPlayRequest(item, next)) }
    connection?.send(
        Wire
            .frame("search")
            .put("request_id", requestId)
            .put("query", "${item.title} ${item.artist}".take(200))
            .put("scope", "catalog"),
    )
    autoPlayTimeout?.cancel()
    autoPlayTimeout =
        viewModelScope.launch {
            delay(AUTO_PLAY_TIMEOUT_MS)
            if (mutable.value.autoPlayRequest != null) failAutoPlay("${item.title} did not reach Music in time. Try again.")
        }
}

internal fun RemoteModel.resolveAutoPlay(songs: List<Song>) {
    val request = mutable.value.autoPlayRequest ?: return
    autoPlayId = null
    val song = songs.firstOrNull { request.item.matches(it) }
    if (song == null) {
        failAutoPlay("Apple Music has no match for ${request.item.title} by ${request.item.artist}.")
        return
    }
    mutable.update { it.copy(autoPlayRequest = request.copy(song = song)) }
    if (mutable.value.preparedSong == preparedKey(song)) sendAutoPlay(song) else prepare(song)
}

/** Called when the Host reports the song prepared. Only the song this request is waiting for is sent. */
internal fun RemoteModel.autoPlayPrepared(prepared: String) {
    val song = mutable.value.autoPlayRequest?.song ?: return
    if (preparedKey(song) == prepared) sendAutoPlay(song)
}

internal fun RemoteModel.failAutoPlay(message: String) {
    autoPlayId = null
    autoPlayTimeout?.cancel()
    mutable.update { it.copy(autoPlayRequest = null, notice = Notice(message)) }
}

private fun RemoteModel.sendAutoPlay(song: Song) {
    val request = mutable.value.autoPlayRequest ?: return
    autoPlayTimeout?.cancel()
    val state = mutable.value
    mutable.update { it.copy(autoPlayRequest = null) }
    if (!request.next && !state.mayInterruptCurrent()) {
        showError(
            "Play now unavailable",
            "Another person's request is playing, so Play now would jump ahead of it. Use Play next instead.",
        )
        return
    }
    val action =
        if (request.next) {
            JSONObject().put("kind", "queue.play_next").put("song", song.identity.json())
        } else {
            JSONObject()
                .put("kind", "queue.play_now")
                .put("song", song.identity.json())
                .put("occurrence_id", state.snapshot?.current?.occurrenceId ?: JSONObject.NULL)
        }
    command(action, "enqueue:" + preparedKey(song), song)
}

private fun preparedKey(song: Song): String = song.source + ":" + song.id
