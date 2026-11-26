package app.cadenza.remote.model

import androidx.lifecycle.viewModelScope
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.nullableString
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.json.JSONObject

// A music video plays in Music's own window, started by the Host. It is never queued, so the queue keeps its place.
internal fun RemoteModel.playVideo(song: Song) {
    if (!mutable.value.connected) {
        mutable.update { it.copy(notice = Notice("Connect to Cadenza Host to play a music video.")) }
        return
    }
    val requestId = id()
    videoPlayId = requestId
    connection?.send(Wire.frame("video.play").put("request_id", requestId).put("song", song.identity.json()))
    mutable.update { it.copy(notice = Notice("Starting the music video in Music.")) }
    viewModelScope.launch {
        delay(VIDEO_PLAY_TIMEOUT_MS)
        if (videoPlayId == requestId) {
            videoPlayId = null
            mutable.update { it.copy(notice = Notice("Music did not start this video. Try again.")) }
        }
    }
}

internal fun RemoteModel.videoStarted(frame: JSONObject) {
    if (frame.nullableString("request_id") != videoPlayId) return
    videoPlayId = null
    mutable.update { it.copy(notice = Notice("Playing the music video in Music.")) }
}

// The Host waits up to 8 seconds for Music to show the video, so the request is given a little longer than that.
private const val VIDEO_PLAY_TIMEOUT_MS = 20_000L
