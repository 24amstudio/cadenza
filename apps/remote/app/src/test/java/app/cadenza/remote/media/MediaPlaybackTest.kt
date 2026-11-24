package app.cadenza.remote.media

import android.media.session.PlaybackState
import app.cadenza.remote.data.LyricLine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TransportTimingTest {
    @Test
    fun playingAdvancesAtNormalSpeedAndPausedHoldsStill() {
        val playing = transportTiming(playing = true, positionMs = 42_000, nowElapsedMs = 900)
        val paused = transportTiming(playing = false, positionMs = 42_000, nowElapsedMs = 900)

        assertEquals(PlaybackState.STATE_PLAYING, playing.state)
        assertEquals(1f, playing.speed)
        assertEquals(PlaybackState.STATE_PAUSED, paused.state)
        assertEquals(0f, paused.speed)
        assertEquals(900L, paused.updatedAtMs)
    }

    @Test
    fun aNegativePositionNeverReachesTheSystemScrubber() {
        assertEquals(0L, transportTiming(playing = true, positionMs = -5, nowElapsedMs = 1).positionMs)
    }
}

class LyricSubtextTest {
    private val lines =
        listOf(
            LyricLine(id = "1", text = "First line", startMs = 1_000, endMs = 4_000, translation = null),
            LyricLine(id = "2", text = "Second line", startMs = 4_000, endMs = 8_000, translation = null),
        )

    @Test
    fun theSoundingLineIsShownOnlyWhileTheScreenIsOn() {
        assertEquals("First line", lyricSubtext(lines, positionMs = 2_000, screenInteractive = true))
        assertNull(lyricSubtext(lines, positionMs = 2_000, screenInteractive = false))
    }

    @Test
    fun untimedOrMissingLyricsLeaveTheSubtextEmpty() {
        val untimed = listOf(LyricLine(id = "1", text = "Untimed", startMs = 0, endMs = 0, translation = null))

        assertNull(lyricSubtext(untimed, positionMs = 2_000, screenInteractive = true))
        assertNull(lyricSubtext(null, positionMs = 2_000, screenInteractive = true))
    }

    @Test
    fun theNextWakeUpIsTheFirstBoundaryAfterThePosition() {
        assertEquals(4_000L, nextLyricChangeMs(lines, positionMs = 2_000))
        assertNull(nextLyricChangeMs(lines, positionMs = 9_000))
    }
}
