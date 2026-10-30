package app.cadenza.remote

import app.cadenza.remote.data.HostSnapshot
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.Wire
import app.cadenza.remote.recommendation.RecommendationFeedback
import app.cadenza.remote.recommendation.RecommendationOutcome
import app.cadenza.remote.recommendation.RecommendationTrack
import app.cadenza.remote.recommendation.newRecommendationId
import kotlinx.coroutines.withContext
import org.json.JSONObject

internal fun RemoteModel.enrichArtwork(snapshot: HostSnapshot): HostSnapshot {
    val currentSong =
        mutable.value.snapshot
            ?.current
            ?.song
    val queueSongs =
        mutable.value.snapshot
            ?.queue
            .orEmpty()
            .map { it.song }
    val known = mutable.value.favorites + mutable.value.results + listOfNotNull(currentSong) + queueSongs
    val artwork = known.filter { it.artworkUrl != null }.associateBy { it.source + ":" + it.id }

    fun song(value: Song): Song = value.artworkUrl?.let { value } ?: artwork[value.source + ":" + value.id] ?: value
    return snapshot.copy(
        current = snapshot.current?.copy(song = song(snapshot.current.song)),
        queue = snapshot.queue.map { it.copy(song = song(it.song)) },
        incoming = snapshot.incoming?.let(::song),
    )
}

internal suspend fun RemoteModel.applyCredit(frame: JSONObject) {
    val host = mutable.value.profile?.hostId ?: return
    val song = frame.getJSONObject("song")
    if (frame.optInt("play_count_delta", 0) == 1) {
        val track = RecommendationTrack(song.getString("source"), song.getString("id"))
        val feedback =
            RecommendationFeedback(
                recommendationId = frame.optString("recommendation_id", newRecommendationId()),
                outcome = RecommendationOutcome.QUALIFIED_PLAY,
                track = track,
                positionMs = frame.optLong("played_ms_delta", 0),
            )
        recommendationEngine.recordFeedback(feedback)
        sendRecommendationFeedback(feedback)
        withContext(updateDispatcher) {
            updateApp.database.saveRecommendationEvent(
                eventId = frame.getString("event_id"),
                recommendationId = feedback.recommendationId,
                source = track.source,
                songId = track.id,
                outcome = feedback.outcome.wire,
                positionMs = feedback.positionMs,
                durationMs = null,
                replacementJson = null,
                occurredAtMs = feedback.occurredAtMs,
            )
        }
    }
    val cursor =
        withContext(updateDispatcher) {
            frame.optJSONObject("song_metadata")?.let { updateApp.database.remember(host, listOf(Wire.song(it))) }
            updateApp.database.applyCredit(host, frame)
        }
    connection?.send(Wire.frame("analytics.ack").put("sequence", cursor))
    reloadStatistics()
}
