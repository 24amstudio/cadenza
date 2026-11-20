package app.cadenza.remote

import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.applyRecommendationResult
import kotlinx.coroutines.Dispatchers
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31])
class RecommendationResultTest {
    private val app get() = ApplicationProvider.getApplicationContext<CadenzaApplication>()

    @Test
    fun hostEvidenceStringsReachTheRecommendation() {
        val model = RemoteModel(app, ioDispatcher = Dispatchers.Unconfined)
        val result =
            JSONObject()
                .put("recommendation_id", "recommendation-1")
                .put("plan_id", "plan-1")
                .put("confidence", 0.8)
                .put("expires_at_ms", 4_102_444_800_000L)
                .put("evidence", JSONArray(listOf("recent listening", "kept after this song")))
                .put("candidate", JSONObject().put("source", "library").put("id", "song-1"))

        model.applyRecommendationResult(JSONObject().put("recommendation_result", result))

        val recommendation = model.state.value.nextRecommendation
        assertEquals(listOf("recent listening", "kept after this song"), recommendation?.evidence)
    }
}
