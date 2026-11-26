package app.cadenza.remote.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TvStageStateTest {
    private val suite =
        TvStageSuite(
            trackId = "abc",
            title = "Pedida",
            artist = "Akad",
            album = "Album",
            durationMs = 214_000L,
            quality = null,
            artworkUrl = null,
            motionUrl = null,
            lines = emptyList(),
        )

    @Test
    fun pairingShowsThePinUntilTheReceiverIsAccepted() {
        val pairing = TvStageState().reduce(TvStageMessage.Pairing("0427", 300_000L), elapsedMs = 1_000L)
        assertEquals(TvStageState.Phase.PAIRING, pairing.phase)
        assertEquals("0427", pairing.pin)
        assertEquals(301_000L, pairing.pinExpiresAtMs)

        val accepted = pairing.reduce(TvStageMessage.Accepted("t".repeat(32)), elapsedMs = 2_000L)
        assertEquals(TvStageState.Phase.READY, accepted.phase)
        assertNull(accepted.pin)
    }

    @Test
    fun aSuiteStartsPlayingFromZeroAndAdvancesWithTheClock() {
        val state = TvStageState().reduce(TvStageMessage.Suite(suite), elapsedMs = 5_000L)
        assertTrue(state.playing)
        assertEquals(0L, state.positionAt(5_000L))
        assertEquals(1_500L, state.positionAt(6_500L))
    }

    @Test
    fun aPositionNeverRunsPastTheTrackEnd() {
        val state = TvStageState().reduce(TvStageMessage.Suite(suite), elapsedMs = 0L)
        assertEquals(214_000L, state.positionAt(10_000_000L))
    }

    @Test
    fun aPauseHoldsThePositionAndAResumeContinuesFromIt() {
        val playing = TvStageState().reduce(TvStageMessage.Suite(suite), elapsedMs = 0L)
        val paused =
            playing.reduce(
                TvStageMessage.Optimistic(isPlaying = false, targetPositionMs = 42_000L, playbackRate = 1.0),
                elapsedMs = 10_000L,
            )
        assertFalse(paused.playing)
        assertEquals(42_000L, paused.positionAt(60_000L))

        val resumed =
            paused.reduce(
                TvStageMessage.Optimistic(isPlaying = true, targetPositionMs = 42_000L, playbackRate = 1.0),
                elapsedMs = 60_000L,
            )
        assertEquals(43_000L, resumed.positionAt(61_000L))
    }

    @Test
    fun aCalibrationCorrectsDriftWithoutChangingPlayState() {
        val playing = TvStageState().reduce(TvStageMessage.Suite(suite), elapsedMs = 0L)
        val calibrated = playing.reduce(TvStageMessage.Clock(90_000L), elapsedMs = 5_000L)
        assertTrue(calibrated.playing)
        assertEquals(91_000L, calibrated.positionAt(6_000L))
    }

    @Test
    fun aDisconnectStopsPlaybackAndKeepsTheSuiteOnScreen() {
        val state = TvStageState().reduce(TvStageMessage.Suite(suite), elapsedMs = 0L).disconnected()
        assertEquals(TvStageState.Phase.OFFLINE, state.phase)
        assertFalse(state.playing)
        assertEquals("Pedida", state.suite?.title)
    }

    @Test
    fun aSocketUrlIsPlainLanHttpOnly() {
        assertEquals("ws://192.168.1.10:8765/cast/live?role=android_tv_receiver", TvStageConfig.socketUrl("192.168.1.10:8765"))
        assertEquals("ws://192.168.1.10:8765/cast/live?role=android_tv_receiver", TvStageConfig.socketUrl("http://192.168.1.10:8765/"))
        assertNull(TvStageConfig.socketUrl("https://192.168.1.10:8765"))
        assertNull(TvStageConfig.socketUrl("http://192.168.1.10:8765/tv"))
        assertNull(TvStageConfig.socketUrl("   "))
    }

    @Test
    fun theApprovalLinkOpensTheHostWebRemoteWithTheDigitPin() {
        assertEquals("http://192.168.1.10:8765/?stage=0427", TvStageConfig.approvalUrl("192.168.1.10:8765", "0427"))
        assertNull(TvStageConfig.approvalUrl("192.168.1.10:8765", "427"))
        assertNull(TvStageConfig.approvalUrl("192.168.1.10:8765", "04a7"))
        assertNull(TvStageConfig.approvalUrl("https://192.168.1.10:8765", "0427"))
    }

    @Test
    fun aTvStartsTheStageUnlessTheSettingSaysOtherwise() {
        assertTrue(TvStageConfig.startsStage(isTelevision = true, manualSetting = null))
        assertFalse(TvStageConfig.startsStage(isTelevision = true, manualSetting = false))
        assertFalse(TvStageConfig.startsStage(isTelevision = false, manualSetting = null))
        assertTrue(TvStageConfig.startsStage(isTelevision = false, manualSetting = true))
    }

    @Test
    fun retriesBackOffFromOneSecondAndStayBelowThirtySeconds() {
        assertEquals(1_000L, stageRetryDelayMs(0))
        assertEquals(8_000L, stageRetryDelayMs(3))
        assertEquals(30_000L, stageRetryDelayMs(40))
    }
}
