package app.cadenza.remote.recommendation

import org.json.JSONObject

class RecommendationEngine(
    private val signer: RecommendationPassportSigner,
) {
    private var sequence = 0L
    private var passport = emptyPassport(0, 0)
    private val recent = ArrayDeque<RecommendationTrack>()
    private val transitions = linkedMapOf<String, Double>()

    @Synchronized
    fun recordFeedback(feedback: RecommendationFeedback) {
        val key = feedback.track.key
        if (feedback.outcome == RecommendationOutcome.QUALIFIED_PLAY ||
            feedback.outcome == RecommendationOutcome.REPLAY
        ) {
            recent.remove(feedback.track)
            recent.addFirst(feedback.track)
            while (recent.size > 100) recent.removeLast()
            passport.recent.firstOrNull()?.let { from ->
                val edge = from.key + "->" + key
                transitions[edge] = ((transitions[edge] ?: 0.0) + 0.1).coerceIn(0.0, 1.0)
            }
        }
    }

    @Synchronized
    fun passport(nowMs: Long = System.currentTimeMillis()): SignedRecommendationPassport {
        sequence++
        passport =
            RecommendationPassport(
                sequence,
                nowMs,
                nowMs + 24 * 60 * 60 * 1000,
                emptyMap(),
                emptyMap(),
                recent.toList(),
                transitions
                    .toMap()
                    .entries
                    .take(512)
                    .associate { it.key to it.value },
                0.5,
                null,
            )
        val payload = passportJson(passport).toString().toByteArray(Charsets.UTF_8)
        return signer.sign(payload)
    }

    fun passportFrame(nowMs: Long = System.currentTimeMillis()): JSONObject =
        JSONObject()
            .put("type", "recommendation.passport")
            .put("version", 1)
            .put("recommendation_passport", passport(nowMs).json())
}
