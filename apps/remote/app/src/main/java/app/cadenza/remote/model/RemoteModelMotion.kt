package app.cadenza.remote.model

import android.util.Base64
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.nullableString
import app.cadenza.remote.motion.MotionAssembly
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import org.json.JSONObject

// Animated album art is requested for the current occurrence only. Chunks for another occurrence are ignored, and the
// video is published only after its digest verifies and the song is still playing.
internal fun RemoteModel.requestMotion(occurrenceId: String) {
    if (transportMode == "ble" || "motion.host-cache" !in mutable.value.capabilities) return
    motionRequestId = id()
    motionAssembly = null
    connection?.send(Wire.frame("motion.get").put("request_id", motionRequestId).put("occurrence_id", occurrenceId))
}

internal fun RemoteModel.motionUnavailable(frame: JSONObject) {
    val requestId = frame.nullableString("request_id") ?: return
    if (requestId == motionRequestId) motionRequestId = null
}

internal suspend fun RemoteModel.applyMotionChunk(frame: JSONObject) {
    val requestId = frame.nullableString("request_id") ?: return
    if (requestId != motionRequestId) return
    val occurrenceId = frame.nullableString("occurrence_id") ?: return
    if (occurrenceId !=
        mutable.value.snapshot
            ?.current
            ?.occurrenceId
    ) {
        return
    }
    val assembly =
        motionAssembly?.takeIf { it.occurrenceId == occurrenceId }
            ?: MotionAssembly
                .open(occurrenceId, frame.optInt("chunk_count"), frame.optInt("total_bytes"), frame.optString("sha256"))
                ?.also { motionAssembly = it }
            ?: return
    val bytes = runCatching { Base64.decode(frame.optString("data_base64"), Base64.DEFAULT) }.getOrNull() ?: return
    if (!assembly.accept(frame.optInt("chunk_index", -1), bytes) || !assembly.complete) return
    motionAssembly = null
    motionRequestId = null
    val video = assembly.assemble()
    if (video == null) {
        reportLog("warning", "motion.rejected", "Animated artwork failed verification and was not played.")
        return
    }
    val file = withContext(ioDispatcher) { motionStore.save(assembly.sha256, video) }
    if (mutable.value.snapshot
            ?.current
            ?.occurrenceId != occurrenceId
    ) {
        return
    }
    mutable.update { it.copy(motion = MotionVideo(occurrenceId, file)) }
}
