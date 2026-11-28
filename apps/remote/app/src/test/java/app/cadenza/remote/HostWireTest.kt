package app.cadenza.remote

import app.cadenza.remote.data.AudioOutput
import app.cadenza.remote.data.BrowseItem
import app.cadenza.remote.data.BrowseTarget
import app.cadenza.remote.data.BrowseWire
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.Wire
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.model.friendlyHostMessage
import app.cadenza.remote.ui.browse.canBrowse
import app.cadenza.remote.ui.nextRepeatMode
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

class HostWireTest {
    private fun snapshot() =
        JSONObject()
            .put("host_id", UUID(0, 1).toString())
            .put("host_epoch", UUID(0, 2).toString())
            .put("revision", 1)
            .put("sequence", 1)
            .put("host_time_ms", 1_000)
            .put("allow_cross_remote_edits", false)
            .put("playing", true)
            .put("volume", 40)
            .put("queue", JSONArray())
            .put("synchronized", true)

    private fun song(id: String = "123") =
        JSONObject()
            .put("source", "catalog")
            .put("id", id)
            .put("title", "Title")
            .put("artist", "Artist")
            .put("album", "Album")

    @Test
    fun theSnapshotCarriesTheHostsShuffleAndRepeatModes() {
        val value = Wire.snapshot(snapshot().put("shuffle", true).put("repeat", "one"))

        assertTrue(value.shuffle)
        assertEquals("one", value.repeat)
    }

    @Test
    fun aSnapshotSavedBeforeTheModesExistedReadsAsBothOff() {
        val value = Wire.snapshot(snapshot())

        assertFalse(value.shuffle)
        assertEquals("off", value.repeat)
    }

    private fun current(live: Boolean?) =
        JSONObject()
            .put("occurrence_id", UUID(0, 3).toString())
            .put("requester_name", "Remote")
            .put("song", song())
            .put("position_ms", 0)
            .put("sampled_at_host_ms", 1)
            .apply { if (live != null) put("is_live_radio", live) }

    @Test
    fun aRadioStreamIsMarkedLiveAndAHostThatOmitsTheFlagIsNot() {
        assertTrue(Wire.snapshot(snapshot().put("current", current(true))).current!!.isLiveRadio)
        assertFalse(Wire.snapshot(snapshot().put("current", current(null))).current!!.isLiveRadio)
    }

    @Test
    fun aSnapshotCarriesTheCastDevicesAndWhatIsBeingSent() {
        val cast =
            JSONObject()
                .put("presentation", "full_suite")
                .put("devices", JSONArray().put(JSONObject().put("name", "Living Room TV").put("display", "display")))
                .put("transmit", JSONObject().put("state", "transmitting").put("device", "Living Room TV"))

        val value = Wire.snapshot(snapshot().put("cast", cast))

        assertEquals("full_suite", value.cast?.presentation)
        assertEquals(
            "Living Room TV",
            value.cast
                ?.devices
                ?.single()
                ?.name,
        )
        assertEquals("transmitting", value.cast?.transmit?.state)
    }

    @Test
    fun aSnapshotListsApprovedCadenzaTvsAndTheTvsWaitingForAPin() {
        val cast =
            JSONObject()
                .put("presentation", "auto")
                .put("devices", JSONArray())
                .put(
                    "stages",
                    JSONArray().put(
                        JSONObject()
                            .put("receiver_id", "tv-1")
                            .put("name", "Living room")
                            .put("transport", "cadenza_web_tv_stage")
                            .put("transmitting", true),
                    ),
                ).put(
                    "pending_stages",
                    JSONArray()
                        .put(
                            JSONObject()
                                .put("receiver_id", "tv-2")
                                .put("name", "Den")
                                .put("pin", "0427")
                                .put("expires_in_ms", 300000),
                        ).put(JSONObject().put("receiver_id", "tv-3").put("name", "Bad").put("pin", "12")),
                )

        val value = Wire.snapshot(snapshot().put("cast", cast))

        assertEquals(listOf("tv-1"), value.cast?.stages?.map { it.receiverId })
        assertTrue(
            value.cast
                ?.stages
                ?.single()
                ?.transmitting == true,
        )
        assertEquals(listOf("0427"), value.cast?.pendingStages?.map { it.pin })
    }

    @Test
    fun aMalformedCastBlockIsDroppedWithoutHidingTheRestOfTheSnapshot() {
        val value = Wire.snapshot(snapshot().put("cast", JSONObject().put("presentation", "bogus")))

        assertTrue(value.cast == null)
        assertEquals("off", value.repeat)
    }

    @Test
    fun theSnapshotCarriesTheMacsAudioOutputsAndBudgetAndSkipsAMalformedOutput() {
        val speakers =
            JSONObject()
                .put("id", "uid-1")
                .put("name", "Mac speakers")
                .put("transport", "built-in")
                .put("is_default", true)
        val kitchen =
            JSONObject()
                .put("id", "uid-2")
                .put("name", "Kitchen")
        val outputs = JSONArray().put(speakers).put(kitchen)
        val value = Wire.snapshot(snapshot().put("audio_outputs", outputs).put("host_budget", "constrained"))

        assertEquals(listOf(AudioOutput("uid-1", "Mac speakers", "built-in", true)), value.audioOutputs)
        assertEquals("constrained", value.hostBudget)
    }

    @Test
    fun aStreamToARemoteNamesItsTargetOnlyWhileTheHostSendsOne() {
        assertEquals("Living Room iPad", Wire.snapshot(snapshot().put("remote_audio_target", "Living Room iPad")).remoteAudioTarget)
        assertNull(Wire.snapshot(snapshot()).remoteAudioTarget)
    }

    @Test
    fun aMusicVideoIsMarkedAndASongWithoutTheFieldIsASong() {
        assertTrue(Wire.song(song().put("media_type", "musicVideo")).isMusicVideo)
        assertFalse(Wire.song(song()).isMusicVideo)
    }

    @Test
    fun anUnknownRepeatModeIsRejected() {
        assertThrows(IllegalArgumentException::class.java) { Wire.snapshot(snapshot().put("repeat", "twice")) }
    }

    @Test
    fun repeatCyclesOffThenAllThenOneThenOff() {
        assertEquals(listOf("all", "one", "off"), listOf("off", "all", "one").map(::nextRepeatMode))
    }

    @Test
    fun aLyricLineKeepsItsSingerAlignmentAndDefaultsToStart() {
        val lines =
            JSONArray()
                .put(
                    JSONObject()
                        .put("id", "a")
                        .put("text", "First")
                        .put("start_ms", 0)
                        .put("end_ms", 1_000),
                ).put(
                    JSONObject()
                        .put("id", "b")
                        .put("text", "Second")
                        .put("start_ms", 1_000)
                        .put("end_ms", 2_000)
                        .put("align", "end"),
                ).put(
                    JSONObject()
                        .put("id", "c")
                        .put("text", "Together")
                        .put("start_ms", 2_000)
                        .put("end_ms", 3_000)
                        .put("align", "center"),
                )
        val document =
            Wire.lyrics(
                JSONObject()
                    .put("occurrence_id", UUID(0, 3).toString())
                    .put("revision", UUID(0, 4).toString())
                    .put("translation_source", "none")
                    .put("lines", lines),
            )

        assertEquals(listOf("start", "end", "center"), document.lines.map { it.align })
    }

    @Test
    fun aBrowseResultKeepsSongsAndCollectionsInTheirSections() {
        val frame =
            JSONObject()
                .put("type", "browse.result")
                .put(
                    "browse",
                    JSONObject()
                        .put("kind", "artist")
                        .put("id", "42")
                        .put("title", "Artist")
                        .put("detail", "Pop")
                        .put(
                            "sections",
                            JSONArray()
                                .put(
                                    JSONObject()
                                        .put("id", "top_songs")
                                        .put("title", "Top songs")
                                        .put("items", JSONArray().put(JSONObject().put("type", "song").put("song", song()))),
                                ).put(
                                    JSONObject()
                                        .put("id", "albums")
                                        .put("title", "Albums")
                                        .put(
                                            "items",
                                            JSONArray().put(JSONObject().put("type", "album").put("id", "7").put("title", "Album")),
                                        ),
                                ),
                        ),
                )

        val page = BrowseWire.page(frame)

        assertEquals("Pop", page.detail)
        assertTrue(page.sections[0].items.single() is BrowseItem.Track)
        assertEquals("7", (page.sections[1].items.single() as BrowseItem.Collection).id)
    }

    @Test
    fun aBrowseItemOfAnUnknownTypeIsRejectedInsteadOfShownBlank() {
        val section =
            JSONObject()
                .put("id", "x")
                .put("title", "X")
                .put("items", JSONArray().put(JSONObject().put("type", "podcast").put("id", "1").put("title", "T")))
        val frame =
            JSONObject().put(
                "browse",
                JSONObject().put("kind", "album").put("title", "A").put("sections", JSONArray().put(section)),
            )

        assertThrows(IllegalArgumentException::class.java) { BrowseWire.page(frame) }
    }

    @Test
    fun aBrowseTargetSurvivesSavingAndNamesTheSamePageEachTime() {
        val target =
            BrowseTarget(
                "album",
                song =
                    app.cadenza.remote.data
                        .SongIdentity("library", "AB12"),
                title = "Album",
            )

        val restored = BrowseTarget.decode(target.encode())

        assertNotNull(restored)
        assertEquals(target, restored)
        assertEquals("album/library:AB12", restored?.key)
        assertEquals("playlist/ABC", BrowseTarget("playlist", "ABC").key)
    }

    @Test
    fun anArtistOfASongTheHostDoesNotKnowIsBrowsedByNameWhileItsAlbumIsNot() {
        val unknown = Song(source = "unknown", id = "opaque", title = "Song", artist = "Payung Teduh")
        val state = RemoteState(connected = true, capabilities = setOf("library.browse"))
        val artist = BrowseTarget.artist(unknown)

        assertEquals("Payung Teduh", artist.artistName)
        assertEquals("artist", artist.request().getString("kind"))
        assertEquals("Payung Teduh", artist.request().getString("artist_name"))
        assertTrue(canBrowse(state, artist))
        assertFalse(canBrowse(state, BrowseTarget.album(unknown)))
        assertEquals(artist, BrowseTarget.decode(artist.encode()))
    }

    @Test
    fun aScriptFailureShowsItsReasonWithoutThePathOrCode() {
        val raw =
            "/Applications/Cadenza Host.app/Contents/Resources/music.js: execution error: " +
                "Error: Error: The library track is unavailable (-2700)"

        assertEquals("Music can no longer find this song in your library. Search for it again to play it.", friendlyHostMessage(raw))
        assertEquals("Allow Cadenza Host in Accessibility.", friendlyHostMessage("Allow Cadenza Host in Accessibility."))
    }
}
