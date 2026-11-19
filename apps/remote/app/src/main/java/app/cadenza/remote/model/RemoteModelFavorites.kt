package app.cadenza.remote.model

import androidx.lifecycle.viewModelScope
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.Wire
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

private const val RESOLVE_TIMEOUT_MS = 8_000L

// The same song. A row from Music's own queue has no identity of its own, so it is matched by title and artist.
fun Song.matches(other: Song): Boolean =
    identity == other.identity ||
        (
            other.source == "unknown" &&
                title.equals(other.title, ignoreCase = true) &&
                artist.equals(other.artist, ignoreCase = true)
        )

// A Favorite needs a catalog or library identity to be played again later. Music's own queue rows have none, so the Host
// library is searched for the same title and artist, and the match is what gets saved.
internal fun RemoteModel.resolveFavorite(song: Song) {
    if (!mutable.value.connected) {
        showWarning("Connect to Cadenza Host to save this song.")
        return
    }
    reportLog("info", "favorite.resolving", "chars=${song.title.length + song.artist.length}")
    val requestId = id()
    favoriteResolveId = requestId
    mutable.update { it.copy(savingFavorite = true) }
    sendToHost(
        Wire
            .frame("search")
            .put("request_id", requestId)
            .put("query", (song.title + " " + song.artist).take(200))
            .put("scope", "library"),
    )
    favoriteResolveTimeout?.cancel()
    favoriteResolveTimeout =
        viewModelScope.launch {
            delay(RESOLVE_TIMEOUT_MS)
            if (favoriteResolveId == requestId) failFavoriteResolution("Music did not answer. Try saving this song again.")
        }
    resolvingSong = song
}

internal fun RemoteModel.applyFavoriteMatches(songs: List<Song>) {
    val wanted = resolvingSong
    finishFavoriteResolution()
    val match = wanted?.let { target -> songs.firstOrNull { it.source != "unknown" && it.matches(target) } }
    if (match == null) {
        showWarning("This song is not in your Host library, so it cannot be saved to Favorites.")
        return
    }
    toggleFavorite(match)
}

internal fun RemoteModel.failFavoriteResolution(message: String) {
    finishFavoriteResolution()
    showWarning(message)
}

private fun RemoteModel.finishFavoriteResolution() {
    favoriteResolveTimeout?.cancel()
    favoriteResolveId = null
    resolvingSong = null
    mutable.update { it.copy(savingFavorite = false) }
}
