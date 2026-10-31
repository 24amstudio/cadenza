package app.cadenza.remote

import app.cadenza.remote.data.Song
import app.cadenza.remote.recommendation.RecommendationFeedback
import app.cadenza.remote.recommendation.RecommendationOutcome
import app.cadenza.remote.recommendation.RecommendationTrack
import app.cadenza.remote.recommendation.newRecommendationId
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

fun RemoteModel.toggleFavorite(song: Song) {
    if (mutable.value.savingFavorite) return
    val saved = mutable.value.favorites.none { it.identity == song.identity }
    val feedback = recommendationFeedback(song, saved)
    recommendationEngine.recordFeedback(feedback)
    sendRecommendationFeedback(feedback)
    mutable.update { it.copy(savingFavorite = true) }
    updateScope.launch {
        try {
            val library = saveFavorite(song, saved, feedback)
            mutable.update {
                it.copy(
                    favorites = library.songs,
                    unreadableFavorites = library.unreadable,
                    notice = Notice(if (saved) "Saved to Favorites" else "Removed from Favorites"),
                )
            }
        } catch (error: Exception) {
            showError("Could not update Favorites", error.message ?: "Your saved songs were preserved.")
        } finally {
            mutable.update { it.copy(savingFavorite = false) }
        }
    }
}

private fun recommendationFeedback(
    song: Song,
    saved: Boolean,
): RecommendationFeedback =
    RecommendationFeedback(
        recommendationId = newRecommendationId(),
        outcome = if (saved) RecommendationOutcome.FAVORITE else RecommendationOutcome.QUEUE_REMOVAL,
        track = RecommendationTrack(song.source, song.id, song.artist, song.album),
    )

private suspend fun RemoteModel.saveFavorite(
    song: Song,
    saved: Boolean,
    feedback: RecommendationFeedback,
) = withContext(updateDispatcher) {
    updateApp.library.setFavorite(song, saved)
    updateApp.database.saveRecommendationEvent(
        eventId = newRecommendationId(),
        recommendationId = feedback.recommendationId,
        source = song.source,
        songId = song.id,
        outcome = feedback.outcome.wire,
        positionMs = null,
        durationMs = song.durationMs,
        replacementJson = null,
        occurredAtMs = feedback.occurredAtMs,
    )
    updateApp.library.load()
}
