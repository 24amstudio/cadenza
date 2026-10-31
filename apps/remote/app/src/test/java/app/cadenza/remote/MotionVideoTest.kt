package app.cadenza.remote

import android.util.Base64
import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.data.CurrentPlayback
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.applyMotionChunk
import app.cadenza.remote.model.requestMotion
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.security.MessageDigest

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31])
class MotionVideoTest {
    private val app get() = ApplicationProvider.getApplicationContext<CadenzaApplication>()
    private val video = ByteArray(700) { (it % 97).toByte() }

    @Test
    fun aVerifiedVideoIsPublishedForTheSongStillPlaying() =
        runBlocking {
            val model = modelPlaying("occurrence-1")
            model.requestMotion("occurrence-1")

            model.applyMotionChunk(chunk(model, "occurrence-1", video))

            val motion = model.state.value.motion
            val file = motion?.file
            assertEquals("occurrence-1", motion?.occurrenceId)
            assertEquals(video.size.toLong(), file?.length())
        }

    @Test
    fun aVideoForASongThatHasEndedIsDiscarded() =
        runBlocking {
            val model = modelPlaying("occurrence-1")
            model.requestMotion("occurrence-1")
            model.mutable.value = model.mutable.value.copy(snapshot = snapshot("occurrence-2"))

            model.applyMotionChunk(chunk(model, "occurrence-1", video))

            assertNull(model.state.value.motion)
        }

    @Test
    fun aDamagedTransferIsNeverPublished() =
        runBlocking {
            val model = modelPlaying("occurrence-1")
            model.requestMotion("occurrence-1")

            model.applyMotionChunk(chunk(model, "occurrence-1", video, announcedAs = ByteArray(700) { 1 }))

            assertNull(model.state.value.motion)
        }

    private fun modelPlaying(occurrenceId: String): RemoteModel =
        RemoteModel(app, ioDispatcher = Dispatchers.Unconfined).also {
            it.mutable.value =
                it.mutable.value.copy(capabilities = setOf("motion.host-cache"), snapshot = snapshot(occurrenceId))
        }

    private fun snapshot(occurrenceId: String) =
        testSnapshot(
            current =
                CurrentPlayback(
                    occurrenceId = occurrenceId,
                    entryId = "entry",
                    requestedBy = "remote",
                    requesterName = "Living room",
                    song = testSong("1499378108"),
                    positionMs = 0,
                    sampledAtHostMs = 0,
                ),
        )

    private fun chunk(
        model: RemoteModel,
        occurrenceId: String,
        bytes: ByteArray,
        announcedAs: ByteArray = bytes,
    ): JSONObject =
        JSONObject()
            .put("type", "motion.chunk")
            .put("request_id", model.motionRequestId)
            .put("occurrence_id", occurrenceId)
            .put("chunk_index", 0)
            .put("chunk_count", 1)
            .put("total_bytes", bytes.size)
            .put("sha256", sha256(announcedAs))
            .put("data_base64", Base64.encodeToString(bytes, Base64.NO_WRAP))

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
}
