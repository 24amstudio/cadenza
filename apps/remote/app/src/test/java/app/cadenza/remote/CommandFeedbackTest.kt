package app.cadenza.remote

import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.model.OptimisticIntent
import app.cadenza.remote.model.PendingCommand
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.UNCONFIRMED_MESSAGE
import app.cadenza.remote.model.commandResultInternal
import app.cadenza.remote.model.publishOptimisticInternal
import app.cadenza.remote.model.reportFailure
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31])
class CommandFeedbackTest {
    private val app get() = ApplicationProvider.getApplicationContext<CadenzaApplication>()

    private fun modelWithPendingCommand(
        intent: OptimisticIntent? = null,
        ageMs: Long = 0,
    ): RemoteModel =
        RemoteModel(app, ioDispatcher = Dispatchers.Unconfined).also {
            it.pending[COMMAND] =
                PendingCommand(
                    JSONObject(),
                    "playback.pause",
                    Job().apply { complete() },
                    intent,
                    trackedAtElapsedMs = SystemClock.elapsedRealtime() - ageMs,
                )
        }

    private fun result(outcome: String) =
        JSONObject()
            .put("command_id", COMMAND)
            .put("host_epoch", "epoch")
            .put("outcome", outcome)

    @Test
    fun anUnconfirmedAnswerSaysNothingWhileTheHostMayStillBeApplyingTheRequest() =
        runBlocking {
            val model = modelWithPendingCommand(OptimisticIntent.Playing(false), ageMs = 700)
            model.hostSnapshot = testSnapshot(playing = true)

            model.commandResultInternal(result("unconfirmed").put("error_code", "outcome_unknown"))

            val pending = model.pending.getValue(COMMAND)
            assertNull(model.state.value.notice)
            assertTrue(pending.hostUnconfirmed)
            assertFalse(pending.unconfirmed)
        }

    @Test
    fun anAnswerThatStaysUnconfirmedPastTheGracePeriodWarnsOnceAndKeepsItsRecord() =
        runBlocking {
            val model = modelWithPendingCommand(OptimisticIntent.Playing(false), ageMs = 3_500)
            model.hostSnapshot = testSnapshot(playing = true)

            model.commandResultInternal(result("unconfirmed"))
            val first = model.state.value.notice

            model.commandResultInternal(result("unconfirmed"))

            assertEquals(UNCONFIRMED_MESSAGE, first?.message)
            assertEquals(
                first?.id,
                model.state.value.notice
                    ?.id,
            )
            assertTrue(model.pending.getValue(COMMAND).unconfirmed)
        }

    @Test
    fun anAppliedAnswerAfterAnUnconfirmedOneSettlesTheCommand() =
        runBlocking {
            val model = modelWithPendingCommand(ageMs = 700)
            model.hostSnapshot = testSnapshot()
            model.commandResultInternal(result("unconfirmed"))

            model.commandResultInternal(result("applied"))

            assertTrue(model.pending.isEmpty())
            assertNull(model.state.value.notice)
        }

    @Test
    fun anAnswerFromARestartedHostStillSettlesTheCommand() =
        runBlocking {
            val model = modelWithPendingCommand()
            model.hostSnapshot = testSnapshot()

            model.commandResultInternal(result("applied").put("host_epoch", "restarted-epoch"))

            assertTrue(model.pending.isEmpty())
        }

    @Test
    fun aRejectedRequestRevertsItsIntentAndWarnsWithoutOpeningAPrompt() =
        runBlocking {
            val host = testSnapshot(playing = true)
            val model = modelWithPendingCommand(OptimisticIntent.Playing(false))
            model.hostSnapshot = host
            model.publishOptimisticInternal()
            val intended = model.state.value.snapshot
            assertEquals(false, intended?.playing)

            model.commandResultInternal(
                result("rejected")
                    .put("error_code", "native_queue_unavailable")
                    .put("message", "Music did not expose the queue."),
            )

            val state = model.state.value
            val reverted = state.snapshot
            assertEquals(true, reverted?.playing)
            assertNull(state.prompt)
            assertEquals("Music did not expose the queue.", state.notice?.message)
            assertTrue(model.pending.isEmpty())
        }

    @Test
    fun aFatalHostProblemOpensThePromptOnlyOnce() {
        val model = RemoteModel(app, ioDispatcher = Dispatchers.Unconfined)
        val message = "Allow Cadenza Host in Privacy & Security → Accessibility."

        model.reportFailure("music_permission", "Request blocked", message)
        val first = model.state.value.prompt
        model.reportFailure("music_permission", "Request blocked", message)
        val second = model.state.value.prompt

        assertEquals(message, second?.message)
        assertEquals(first?.id, second?.id)
    }

    private companion object {
        const val COMMAND = "command-pending"
    }
}
