package app.cadenza.remote.model

import android.util.Base64
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.objects
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun RemoteModel.applyRecommendationResult(frame: JSONObject) {
    val value = frame.optJSONObject("recommendation_result") ?: return
    val candidate = value.optJSONObject("candidate") ?: return
    val source = candidate.getString("source")
    val songId = candidate.getString("id")
    val queueSongs =
        mutable.value.snapshot?.let { snapshot -> snapshot.queue.map { it.song } } ?: emptyList()
    val knownSongs = mutable.value.favorites + mutable.value.results + queueSongs
    val known = knownSongs.firstOrNull { it.source == source && it.id == songId }
    val item =
        RecommendationItem(
            recommendationId = value.getString("recommendation_id"),
            planId = value.getString("plan_id"),
            source = source,
            songId = songId,
            title = known?.title,
            artist = known?.artist,
            confidence = value.optDouble("confidence", 0.0),
            evidence =
                value
                    .optJSONArray("evidence")
                    ?.objects()
                    ?.map { it.toString() }
                    .orEmpty(),
            expiresAtMs = value.getLong("expires_at_ms"),
        )
    mutable.update {
        it.copy(creeMode = value.optString("mode", "planning"), nextRecommendation = item)
    }
}

internal fun RemoteModel.sendRecommendationPassport() {
    val frame = recommendationEngine.passportFrame().put("request_id", id())
    val signed = frame.getJSONObject("recommendation_passport")
    val payload =
        Base64.decode(
            signed.getString("payload_base64"),
            Base64.NO_WRAP,
        )
    val sequence = JSONObject(String(payload, Charsets.UTF_8)).getLong("sequence")
    updateScope.launch(updateDispatcher) {
        updateApp.database.saveRecommendationPassport(
            sequence,
            signed.getString("payload_base64"),
            signed.getString("public_key_base64"),
            signed.getString("signature_base64"),
            System.currentTimeMillis(),
        )
    }
    connection?.send(frame)
}

internal fun RemoteModel.requestRecommendation() {
    val canRequest =
        mutable.value.connected && mutable.value.profile != null &&
            "recommendations.cree" in mutable.value.capabilities && mutable.value.snapshot != null
    if (!canRequest) return
    connection?.send(
        Wire
            .frame("recommendation.query")
            .put("request_id", id())
            .put(
                "recommendation_query",
                JSONObject()
                    .put("horizon", 1)
                    .put("model_version", 1)
                    .put("filters", JSONObject().put("explicit_allowed", true).put("locked", false)),
            ),
    )
}
