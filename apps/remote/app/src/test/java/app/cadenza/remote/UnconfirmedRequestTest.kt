package app.cadenza.remote

import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.model.PendingCommand
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.checkRequestInternal
import app.cadenza.remote.model.commandResultInternal
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31])
class UnconfirmedRequestTest {
    private val app get() = ApplicationProvider.getApplicationContext<CadenzaApplication>()

    private fun modelWithRestoredRequest(): RemoteModel =
        RemoteModel(app, ioDispatcher = Dispatchers.Unconfined).also {
            it.pending[COMMAND] = PendingCommand(JSONObject(), "playback.skip", Job().apply { complete() })
        }

    private fun unconfirmedResult() =
        JSONObject()
            .put("command_id", COMMAND)
            .put("outcome", "unconfirmed")
            .put("message", "Music did not confirm this request.")

    @Test
    fun aRestoredRequestOnlyAddsANoticeAndNeverOpensThePrompt() =
        runBlocking {
            val model = modelWithRestoredRequest()

            model.commandResultInternal(unconfirmedResult())

            val state = model.state.value
            assertNull(state.prompt)
            assertEquals("Request still needs confirmation", state.notice?.message)
        }

    @Test
    fun aStatusCheckTheUserAskedForExplainsTheOutcomeInAPrompt() =
        runBlocking {
            val model = modelWithRestoredRequest()

            model.checkRequestInternal(COMMAND)
            model.commandResultInternal(unconfirmedResult())

            val prompt = model.state.value.prompt
            assertEquals(COMMAND, prompt?.commandId)
        }

    private companion object {
        const val COMMAND = "command-restored"
    }
}
