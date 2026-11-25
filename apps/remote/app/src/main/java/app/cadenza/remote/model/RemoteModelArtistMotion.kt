package app.cadenza.remote.model

import android.util.Base64
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.nullableString
import app.cadenza.remote.motion.MotionAssembly
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import org.json.JSONObject

// The Host accepts an artist name of 1 to 200 characters. The page never asks with another one.
internal fun artistMotionNameIsValid(name: String): Boolean = name.isNotBlank() && name.length <= 200

// An Artist Details header asks for its artist's motion video. The Host answers under its own request ID, so chunks for a
// request the page has replaced are ignored, and the video is published only after its digest verifies.
internal fun RemoteModel.requestArtistMotion(artistName: String) {
    if (!artistMotionNameIsValid(artistName)) return
    if (transportMode == "ble" || "motion.host-cache" !in mutable.value.capabilities) return
    if (!energy.profile.value.motionArtwork) return
    // Saver and the Host's constrained or survival budget both stop optional video downloads.
    val budget = mutable.value.snapshot?.hostBudget
    if (budget == "constrained" || budget == "survival") return
    val requestId = id()
    artistMotionRequestId = requestId
    artistMotionName = artistName
    artistMotionAssembly = null
    connection?.send(
        Wire.frame("artist.motion.get").put("request_id", requestId).put("artist_name", artistName),
    )
}

internal fun RemoteModel.artistMotionUnavailable(frame: JSONObject) {
    val requestId = frame.nullableString("request_id") ?: return
    if (requestId == artistMotionRequestId) {
        artistMotionRequestId = null
        artistMotionName = null
        artistMotionAssembly = null
    }
}

internal suspend fun RemoteModel.applyArtistMotionChunk(frame: JSONObject) {
    val requestId = frame.nullableString("request_id") ?: return
    if (requestId != artistMotionRequestId) return
    val artistName = artistMotionName ?: return
    val assembly =
        artistMotionAssembly
            ?: MotionAssembly
                .open(requestId, frame.optInt("chunk_count"), frame.optInt("total_bytes"), frame.optString("sha256"))
                ?.also { artistMotionAssembly = it }
            ?: return
    val bytes = runCatching { Base64.decode(frame.optString("data_base64"), Base64.DEFAULT) }.getOrNull() ?: return
    if (!assembly.accept(frame.optInt("chunk_index", -1), bytes) || !assembly.complete) return
    artistMotionAssembly = null
    artistMotionRequestId = null
    val video = assembly.assemble()
    if (video == null) {
        reportLog("warning", "artist.motion.rejected", "Artist artwork failed verification and was not shown.")
        return
    }
    val file = withContext(ioDispatcher) { artistMotionStore.save(assembly.sha256, video) }
    // The page may have moved to another artist while the file was written.
    if (artistMotionName != artistName) return
    mutable.update { it.copy(artistMotion = ArtistMotionVideo(artistName, file)) }
}
