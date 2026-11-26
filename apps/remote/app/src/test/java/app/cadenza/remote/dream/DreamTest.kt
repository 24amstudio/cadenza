package app.cadenza.remote.dream

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DreamActivationEligibilityTest {
    private val playing = DreamConditions(hostConnected = true, hostPlaying = true, hasCurrentSong = true, charging = true)

    @Test
    fun unpluggingEndsTheScreenSaverAtOnce() {
        val eligibility = DreamActivationEligibility()
        assertTrue(eligibility.canActivate(playing, nowMs = 0))

        assertFalse(eligibility.canActivate(playing.copy(charging = false), nowMs = 1))
    }

    @Test
    fun aLostHostEndsTheScreenSaverAtOnce() {
        val eligibility = DreamActivationEligibility()
        assertTrue(eligibility.canActivate(playing, nowMs = 0))

        assertFalse(eligibility.canActivate(playing.copy(hostConnected = false), nowMs = 1))
    }

    @Test
    fun aPauseWithASongLoadedEndsTheScreenSaverAtOnce() {
        val eligibility = DreamActivationEligibility()
        assertTrue(eligibility.canActivate(playing, nowMs = 0))

        assertFalse(eligibility.canActivate(playing.copy(hostPlaying = false), nowMs = 1))
    }

    @Test
    fun aScreenSaverThatStartsWhilePausedNeverGetsTheGrace() {
        val eligibility = DreamActivationEligibility()

        assertFalse(eligibility.canActivate(playing.copy(hostPlaying = false, hasCurrentSong = false), nowMs = 0))
    }

    @Test
    fun aGapBetweenSongsIsToleratedOnlyUntilTheGraceRunsOut() {
        val eligibility = DreamActivationEligibility()
        assertTrue(eligibility.canActivate(playing, nowMs = 0))
        val gap = playing.copy(hostPlaying = false, hasCurrentSong = false)

        assertTrue(eligibility.canActivate(gap, nowMs = 5_000))
        assertFalse(eligibility.canActivate(gap, nowMs = 5_001))
    }

    @Test
    fun aSongStartingInsideTheGapKeepsTheScreenSaverUp() {
        val eligibility = DreamActivationEligibility()
        assertTrue(eligibility.canActivate(playing, nowMs = 0))

        assertTrue(eligibility.canActivate(playing.copy(hostPlaying = false, hasCurrentSong = false), nowMs = 2_000))
        assertTrue(eligibility.canActivate(playing, nowMs = 3_000))
    }
}

class DreamStagesTest {
    @Test
    fun theThreeStagesFollowTheIdleThresholds() {
        assertEquals(DreamStage.AMBIENT, dreamStageFor(0))
        assertEquals(DreamStage.AMBIENT, dreamStageFor(2 * 60_000L - 1))
        assertEquals(DreamStage.DRIFT, dreamStageFor(2 * 60_000L))
        assertEquals(DreamStage.DRIFT, dreamStageFor(10 * 60_000L - 1))
        assertEquals(DreamStage.NIGHT, dreamStageFor(10 * 60_000L))
    }
}
