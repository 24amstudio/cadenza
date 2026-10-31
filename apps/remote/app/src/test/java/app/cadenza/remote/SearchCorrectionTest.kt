package app.cadenza.remote

import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.data.Song
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.receive
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31])
class SearchCorrectionTest {
    private val app get() = ApplicationProvider.getApplicationContext<CadenzaApplication>()
    private val pelukan = Song("catalog", "1234567", "Untuk Perempuan Yang Sedang Di Pelukan", "Payung Teduh")

    @Test
    fun aMissedSearchAlsoSearchesTheKnownTitleItMeant() =
        runBlocking {
            val model = RemoteModel(app, ioDispatcher = Dispatchers.Unconfined)
            model.mutable.value = model.mutable.value.copy(connected = true, favorites = listOf(pelukan))
            model.search("pelukn", library = false)

            model.receive(searchResult(model.searchId, emptyList()))
            assertEquals(pelukan.title, model.state.value.correctedQuery)

            model.receive(searchResult(model.correctionId, listOf(pelukan)))
            assertEquals(
                listOf("1234567"),
                model.state.value.correctedResults
                    .map { it.id },
            )
        }

    private fun searchResult(
        requestId: String?,
        songs: List<Song>,
    ) = JSONObject()
        .put("type", "search.result")
        .put("request_id", requestId)
        .put(
            "songs",
            JSONArray(
                songs.map {
                    JSONObject()
                        .put("source", it.source)
                        .put("id", it.id)
                        .put("title", it.title)
                        .put("artist", it.artist)
                },
            ),
        )
}
