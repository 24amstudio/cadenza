package app.cadenza.remote.tv

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TvStageProtocolTest {
    // The fixtures that the Host, the web stage, and the Node tests also read.
    private val fixtures: JSONObject =
        JSONObject(File("../../../shared/protocol/examples/cast-stage-frames.json").readText())

    private fun hex(text: String): ByteArray = ByteArray(text.length / 2) { text.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    @Test
    fun everyFixtureFrameDecodesToItsDocumentedFields() {
        val frames = fixtures.getJSONArray("frames")
        for (index in 0 until frames.length()) {
            val fixture = frames.getJSONObject(index)
            val expect = fixture.getJSONObject("expect")
            val frame = StageFrameDecoder.decode(hex(fixture.getString("hex")))
            when (val type = expect.getString("type")) {
                "AUDIO_FRAME" -> {
                    val audio = frame as StageFrame.Audio
                    assertEquals(type, "AUDIO_FRAME")
                    assertEquals(expect.getInt("codec"), audio.codec)
                    assertEquals(expect.getInt("channels"), audio.channels)
                    assertEquals(expect.getInt("sampleRate"), audio.sampleRate)
                    assertEquals(expect.getLong("presentationTimeUs"), audio.presentationTimeUs)
                    assertArrayEquals(hex(expect.getString("payloadHex")), audio.payload)
                }
                "INIT_SEGMENT" -> assertEquals(expect.getInt("codec"), (frame as StageFrame.InitSegment).codec)
                "FLUSH_STREAM" -> assertEquals(expect.getLong("generationSeq"), (frame as StageFrame.Flush).generationSeq)
                else -> throw AssertionError("unexpected fixture type $type")
            }
        }
    }

    @Test
    fun everyMalformedFixtureIsRefused() {
        val rejects = fixtures.getJSONArray("rejects")
        for (index in 0 until rejects.length()) {
            val bytes = hex(rejects.getJSONObject(index).getString("hex"))
            assertThrows(rejects.getJSONObject(index).getString("name"), StageFrameException::class.java) {
                StageFrameDecoder.decode(bytes)
            }
        }
    }

    @Test
    fun aTrackSuiteParsesWithItsLinesAndWordsAndAnOptionalBadge() {
        val text =
            """
            {"version":1,"type":"TRACK_SUITE_PAYLOAD","trackId":"abc","title":"Pedida","artist":"Akad","album":"Album",
             "durationMs":214000,"artworkUrl":"http://192.168.1.10:8765/api/v1/cast/artwork/abc.jpg",
             "lines":[{"id":"l1","text":"Hello","start_ms":1000,"end_ms":2000,
               "words":[{"text":"Hello","start_ms":1000,"end_ms":2000}],"translation":"Halo","align":"end"}]}
            """.trimIndent()
        val message = TvStageMessages.parse(text) as TvStageMessage.Suite
        assertEquals("Pedida", message.suite.title)
        assertNull(message.suite.quality)
        assertEquals("Halo", message.suite.lines[0].translation)
        assertEquals("end", message.suite.lines[0].align)
        val centered = text.replace("\"align\":\"end\"", "\"align\":\"center\"")
        assertEquals("center", (TvStageMessages.parse(centered) as TvStageMessage.Suite).suite.lines[0].align)
        assertEquals(
            1,
            message.suite.lines[0]
                .words.size,
        )
    }

    @Test
    fun unknownFieldsAndOutOfRangeValuesAreRefused() {
        assertNull(
            TvStageMessages.parse(
                """{"version":1,"type":"CLOCK_CALIBRATE","actualPositionMs":1,"audioLatencyMs":0,"hostMonoTimeMs":0,"extra":true}""",
            ),
        )
        assertNull(TvStageMessages.parse("""{"version":1,"type":"REMOTE_COMMAND"}"""))
        assertNull(
            TvStageMessages.parse(
                """{"version":1,"type":"OPTIMISTIC_STATE","isPlaying":true,"targetPositionMs":-1,"playbackRate":1,"hostMonoTimeMs":0,"audioLatencyMs":0}""",
            ),
        )
        assertNull(
            TvStageMessages.parse(
                """{"version":1,"type":"OPTIMISTIC_STATE","isPlaying":true,"targetPositionMs":1,"playbackRate":0,"hostMonoTimeMs":0,"audioLatencyMs":0}""",
            ),
        )
        assertNull(TvStageMessages.parse("not json"))
    }

    @Test
    fun aVideoMustBeAPlainLanMp4WithItsSubtitleTrack() {
        val valid =
            """{"version":1,"type":"VIDEO_KARAOKE_PAYLOAD","source":"lan_mp4","mediaUrl":"http://192.168.1.10:8765/api/v1/cast/video/abc/video.mp4","subtitleUrl":"http://192.168.1.10:8765/api/v1/cast/video/abc/lyrics.vtt","userOffsetMs":-500}"""
        assertTrue(TvStageMessages.parse(valid) is TvStageMessage.Video)
        assertNull(TvStageMessages.parse(valid.replace("lan_mp4", "airplay_hls_proxy")))
        assertNull(
            TvStageMessages.parse(
                valid.replace("http://192.168.1.10:8765/api/v1/cast/video/abc/video.mp4", "https://cdn.example/video.m3u8"),
            ),
        )
    }

    @Test
    fun aProfileNamesTheAndroidTransportAndCarriesOnlyWhatTheOutputPlays() {
        val profile = JSONObject(TvStageMessages.profile("tv-1", "Cadenza TV", 6, listOf("pcm", "ac-3"), 30, null))
        assertEquals("cadenza_android_tv_receiver", profile.getString("transportType"))
        assertEquals(JSONArray(listOf("pcm", "ac-3")).toString(), profile.getJSONArray("supportedCodecs").toString())
        assertEquals(false, profile.has("receiverToken"))
        val withToken = JSONObject(TvStageMessages.profile("tv-1", "Cadenza TV", 2, listOf("pcm"), 0, "t".repeat(32)))
        assertEquals("t".repeat(32), withToken.getString("receiverToken"))
    }

    @Test
    fun aCommandIsOnlyBuiltForAStageAction() {
        assertEquals("playback.skip", JSONObject(TvStageMessages.command("playback.skip")!!).getString("action"))
        assertNull(TvStageMessages.command("queue.play_now"))
    }

    @Test
    fun aPairingPinMustBeFourDigits() {
        assertNotNull(TvStageMessages.parse("""{"version":1,"type":"STAGE_PAIRING","pin":"0427","expiresInMs":300000}"""))
        assertNull(TvStageMessages.parse("""{"version":1,"type":"STAGE_PAIRING","pin":"427","expiresInMs":300000}"""))
    }
}
