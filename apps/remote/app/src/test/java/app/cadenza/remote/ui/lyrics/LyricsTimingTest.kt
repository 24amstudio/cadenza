package app.cadenza.remote.ui.lyrics

import app.cadenza.remote.data.LyricLine
import app.cadenza.remote.data.LyricWord
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LyricsTimingTest {
    private fun line(
        id: String,
        startMs: Long,
        endMs: Long,
        vararg words: LyricWord,
    ) = LyricLine(id, id, startMs, endMs, null, words.toList())

    private val chorus =
        line("main", 0, 4_000, LyricWord("la ", 0, 1_000), LyricWord("la ", 1_000, 2_000), LyricWord("la", 2_000, 4_000))
    private val background = line("background", 1_500, 3_000, LyricWord("ooh", 1_500, 3_000))

    @Test
    fun newestActiveLineIsTheLastLineSoundingAtThePosition() {
        val lines = listOf(chorus, background, line("untimed", 5_000, 5_000))
        for (position in listOf(-1L, 0L, 1_499L, 1_500L, 2_999L, 3_000L, 4_000L, 9_000L)) {
            assertEquals(activeLineIndices(lines, position).lastOrNull() ?: -1, newestActiveLine(lines, position))
        }
        assertEquals(1, newestActiveLine(lines, 2_000))
        assertEquals(0, newestActiveLine(lines, 3_500))
        assertEquals(-1, newestActiveLine(lines, -1))
    }

    @Test
    fun wordFillsSweepOnlyTheLatestStartedWordOfTheSweepingLine() {
        assertArrayEquals(floatArrayOf(1f, 0.5f, 0f), wordFills(chorus, 1_500, sweeping = true), 0.001f)
        assertArrayEquals(floatArrayOf(1f, 1f, 0.25f), wordFills(chorus, 2_500, sweeping = true), 0.001f)
        assertArrayEquals(floatArrayOf(0f, 0f, 0f), wordFills(chorus, 0, sweeping = true), 0.001f)
    }

    @Test
    fun linesThatDoNotSweepShowWholeStartedWords() {
        assertArrayEquals(floatArrayOf(1f, 1f, 0f), wordFills(chorus, 1_500, sweeping = false), 0.001f)
        assertEquals(2, litWordCount(chorus.words, 1_500))
        assertEquals(0, litWordCount(chorus.words, -1))
    }

    @Test
    fun overlappingBackgroundVocalsTakeTheSweepFromTheMainLine() {
        val lines = listOf(chorus, background)
        assertEquals(SweepTarget(0, 1), sweepTarget(lines, 1_200))
        assertEquals(SweepTarget(1, 0), sweepTarget(lines, 2_000))
        assertEquals(SweepTarget(0, 2), sweepTarget(lines, 3_500))
    }

    @Test
    fun noWordSweepsBeforeTheFirstWordStarts() {
        val late = line("late", 1_000, 3_000, LyricWord("hello", 1_500, 2_500))
        assertNull(sweepTarget(listOf(late), 500))
        assertNull(sweepTarget(listOf(late), 1_200))
        assertEquals(SweepTarget(0, 0), sweepTarget(listOf(late), 1_500))
    }

    @Test
    fun sweepEdgeIsHardAtBothEndsAndWidestInTheMiddle() {
        assertEquals(0f, sweepEdgeFraction(0f), 0.0001f)
        assertEquals(0f, sweepEdgeFraction(1f), 0.0001f)
        assertEquals(0.12f, sweepEdgeFraction(0.5f), 0.0001f)
        assertEquals(sweepEdgeFraction(0.2f), sweepEdgeFraction(0.8f), 0.0001f)
    }

    @Test
    fun tiersRecedeWithDistanceFromTheActiveLines() {
        val active = listOf(4, 5)
        assertEquals(TIER_ACTIVE, lyricTier(5, active), 0f)
        assertEquals(TIER_NEAR, lyricTier(3, active), 0f)
        assertEquals(TIER_FAR, lyricTier(0, active), 0f)
        assertEquals(TIER_NEAR, lyricTier(0, emptyList()), 0f)
        assertEquals(1f, tierOpacity(TIER_ACTIVE), 0f)
        assertEquals(0.425f, tierOpacity(1.5f), 0.0001f)
        assertEquals(tierOpacity(TIER_FAR), tierOpacity(7f), 0f)
    }
}
