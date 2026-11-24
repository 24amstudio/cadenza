package app.cadenza.remote.widget

import org.junit.Assert.assertEquals
import org.junit.Test

class LyricWindowTest {
    private val lines =
        listOf("first", "second", "third", "fourth").mapIndexed { index, text ->
            WidgetLyric(text = text, end = index == 2)
        }

    @Test
    fun theActiveLineIsCenteredAndKeepsItsSingerAlignment() {
        val window = lyricWindow(lines, activeIndex = 1)

        assertEquals("second", window[ACTIVE].text)
        assertEquals(WidgetLyric(text = "third", end = true), window[ACTIVE + 1])
    }

    @Test
    fun theWindowIsPaddedAtTheSongsEdges() {
        val window = lyricWindow(lines, activeIndex = 0)

        assertEquals("", window[0].text)
        assertEquals("first", window[ACTIVE].text)
        assertEquals("second", window[LYRIC_WINDOW - 1].text)
    }

    @Test
    fun noActiveLineMeansAnEmptyWindow() {
        assertEquals(List(LYRIC_WINDOW) { WidgetLyric(text = "", end = false) }, lyricWindow(lines, activeIndex = null))
    }
}
