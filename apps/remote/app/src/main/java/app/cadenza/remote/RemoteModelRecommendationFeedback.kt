package app.cadenza.remote

import app.cadenza.remote.data.Wire
import app.cadenza.remote.recommendation.RecommendationFeedback
import app.cadenza.remote.recommendation.RecommendationOutcome
import app.cadenza.remote.recommendation.RecommendationTrack
import app.cadenza.remote.recommendation.newRecommendationId
import app.cadenza.remote.recommendation.trackJson
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun RemoteModel.recordRecommendationCommand(action: JSONObject) {
    val current = mutable.value.snapshot?.current ?: return
    val outcome =
        when (action.optString("kind")) {
            "playback.skip" -> {
                val duration = current.song.durationMs ?: Long.MAX_VALUE
                if (current.positionMs * 4 < duration) RecommendationOutcome.EARLY_SKIP else RecommendationOutcome.LATE_SKIP
            }
            "queue.remove" -> RecommendationOutcome.QUEUE_REMOVAL
            "queue.enqueue", "queue.play_next" -> RecommendationOutcome.MANUAL_REPLACEMENT
            else -> return
        }
    val replacement =
        action.optJSONObject("song")?.let {
            RecommendationTrack(it.getString("source"), it.getString("id"))
        }
    val item = mutable.value.nextRecommendation
    val track = RecommendationTrack(current.song.source, current.song.id, current.song.artist, current.song.album)
    val feedback =
        RecommendationFeedback(
            recommendationId = item?.recommendationId ?: newRecommendationId(),
            outcome = outcome,
            track = track,
            positionMs = current.positionMs,
            durationMs = current.song.durationMs,
            replacement = replacement,
        )
    recommendationEngine.recordFeedback(feedback)
    sendRecommendationFeedback(feedback)
    updateScope.launch(updateDispatcher) {
        updateApp.database.saveRecommendationEvent(
            eventId = newRecommendationId(),
            recommendationId = feedback.recommendationId,
            source = feedback.track.source,
            songId = feedback.track.id,
            outcome = outcome.wire,
            positionMs = feedback.positionMs,
            durationMs = feedback.durationMs,
            replacementJson = feedback.replacement?.let(::trackJson)?.toString(),
            occurredAtMs = feedback.occurredAtMs,
        )
    }
}

internal fun RemoteModel.sendRecommendationFeedback(feedback: RecommendationFeedback) {
    if (!mutable.value.connected || "recommendations.cree" !in mutable.value.capabilities) return
    val payload =
        JSONObject()
            .put("recommendation_id", feedback.recommendationId)
            .put("outcome", feedback.outcome.wire)
            .put("track", trackJson(feedback.track))
            .put("occurred_at_ms", feedback.occurredAtMs)
    feedback.positionMs?.let { payload.put("position_ms", it) }
    feedback.durationMs?.let { payload.put("duration_ms", it) }
    feedback.replacement?.let { payload.put("replacement", trackJson(it)) }
    connection?.send(Wire.frame("recommendation.feedback").put("recommendation_feedback", payload))
}
