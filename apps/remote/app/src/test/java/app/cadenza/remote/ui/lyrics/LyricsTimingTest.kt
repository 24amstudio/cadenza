package app.cadenza.remote.ui.lyrics

import androidx.compose.ui.text.style.TextAlign
import app.cadenza.remote.data.LyricLine
import app.cadenza.remote.data.LyricWord
import org.junit.Assert.assertEquals
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
    fun linesThatDoNotSweepShowWholeStartedWords() {
        assertEquals(2, litWordCount(chorus.words, 1_500))
        assertEquals(0, litWordCount(chorus.words, -1))
    }

    @Test
    fun everySoundingLineSweepsItsOwnWordAtTheSameTime() {
        val lines = listOf(chorus, background)
        assertEquals(mapOf(0 to 1..1), sweepTargets(lines, 1_200))
        // The background line starts while the main line is still on its second word: both sweep.
        assertEquals(mapOf(0 to 1..1, 1 to 0..0), sweepTargets(lines, 1_700))
        assertEquals(mapOf(0 to 2..2, 1 to 0..0), sweepTargets(lines, 2_500))
        // After the background line ends only the main line is left.
        assertEquals(mapOf(0 to 2..2), sweepTargets(lines, 3_500))
        assertEquals(emptyMap<Int, IntRange>(), sweepTargets(lines, 4_000))
    }

    @Test
    fun overlappingWordsOfOneLineSweepTogether() {
        val overlapping = line("overlap", 0, 2_000, LyricWord("a ", 0, 1_200), LyricWord("b ", 1_000, 2_000), LyricWord("c", 1_900, 2_000))
        assertEquals(0..0, soundingWords(overlapping.words, 500))
        assertEquals(0..1, soundingWords(overlapping.words, 1_100))
        assertEquals(1..2, soundingWords(overlapping.words, 1_950))
        assertEquals(IntRange.EMPTY, soundingWords(overlapping.words, 2_000))
    }

    @Test
    fun noWordSweepsBeforeTheFirstWordStarts() {
        val late = line("late", 1_000, 3_000, LyricWord("hello", 1_500, 2_500))
        assertEquals(emptyMap<Int, IntRange>(), sweepTargets(listOf(late), 500))
        assertEquals(emptyMap<Int, IntRange>(), sweepTargets(listOf(late), 1_200))
        assertEquals(mapOf(0 to 0..0), sweepTargets(listOf(late), 1_500))
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

    @Test
    fun activeLineSitsBelowTwoLinesAtTheTopOfTheViewport() {
        // Two lines of 60 px with 17 px gaps above the active line: the first of them goes to the top edge.
        val leadTop = 300f
        val anchorTop = leadTop + 2 * 77f
        assertEquals(300f, leadAlignDelta(leadTop, anchorTop, viewportHeight = 1_000f, restPx = 0f), 0.001f)
    }

    @Test
    fun tallLinesAboveTheActiveLineAreClippedInsteadOfPushingItPastTheCap() {
        val span = 600f
        val delta = leadAlignDelta(leadTop = 0f, anchorTop = span, viewportHeight = 1_000f, restPx = 0f)
        // The active line is held at the cap, so the first lead line moves 200 px above the viewport top.
        assertEquals(1_000f * ANCHOR_MAX_FRACTION - span, -delta, 0.001f)
    }

    @Test
    fun openingLinesRestAtTheTopPaddingUntilTwoLinesPrecedeTheActiveOne() {
        val rest = 140f
        assertEquals(0f, leadAlignDelta(leadTop = rest, anchorTop = rest + 77f, viewportHeight = 1_000f, restPx = rest), 0.001f)
    }

    @Test
    fun secondSingerLinesAlignToTheEndAndGroupLinesToTheMiddle() {
        assertEquals(TextAlign.Start, lyricTextAlign(line("a", 0, 1_000)))
        assertEquals(TextAlign.End, lyricTextAlign(line("b", 0, 1_000).copy(align = "end")))
        assertEquals(TextAlign.Center, lyricTextAlign(line("c", 0, 1_000).copy(align = "center")))
    }

    @Test
    fun blurReachesOnlyTheLinesNearTheActiveOnes() {
        assertEquals(listOf(false, true, true, true, true, true, false), (0..6).map { inBlurWindow(it, listOf(3), 2) })
        assertEquals(false, inBlurWindow(3, listOf(3), 0))
        assertEquals(true, inBlurWindow(1, emptyList(), 2))
        assertEquals(false, inBlurWindow(2, emptyList(), 2))
    }

    @Test
    fun theFrameCapSleepsBetweenSamplesAndNeverUncaps() {
        assertEquals(42L, frameGapMs(20))
        assertEquals(8L, frameGapMs(60))
        assertEquals(0L, frameGapMs(240))
        assertEquals(992L, frameGapMs(0))
    }
}
