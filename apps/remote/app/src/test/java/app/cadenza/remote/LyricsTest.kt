package app.cadenza.remote

import app.cadenza.remote.data.LyricDocument
import app.cadenza.remote.data.LyricLine
import app.cadenza.remote.data.LyricWord
import app.cadenza.remote.data.Wire
import app.cadenza.remote.ui.activeLyricIndex
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class LyricsTest {
    @Test
    fun lyricLevelDistinguishesPlainLineAndWordTimedDocuments() {
        val empty = LyricDocument("a", "b", "none", emptyList(), null)
        val plain = LyricDocument("a", "b", "original", listOf(LyricLine("1", "Plain", 0, 0, null)), null)
        val lineTimed = plain.copy(lines = listOf(LyricLine("1", "Timed", 0, 1_000, null)))
        val wordTimed =
            lineTimed.copy(
                lines =
                    listOf(
                        LyricLine("1", "Timed", 0, 1_000, null, listOf(LyricWord("Timed", 0, 500))),
                    ),
            )
        assertEquals(0, empty.level)
        assertEquals(1, plain.level)
        assertEquals(2, lineTimed.level)
        assertEquals(3, wordTimed.level)
    }

    @Test
    fun highlightingRequiresCurrentOccurrenceAndLiveTimedPosition() {
        val document =
            LyricDocument(
                "occurrence-a",
                "revision-a",
                "original",
                listOf(
                    LyricLine("first", "First", 0, 1_000, null),
                    LyricLine("second", "Second", 1_000, 2_000, null),
                    LyricLine("untimed", "Untimed", 2_000, 2_000, null),
                ),
                null,
            )
        assertEquals(0, activeLyricIndex(document, "occurrence-a", 999, true))
        assertEquals(1, activeLyricIndex(document, "occurrence-a", 1_000, true))
        assertEquals(-1, activeLyricIndex(document, "occurrence-a", 2_000, true))
        assertEquals(-1, activeLyricIndex(document, "occurrence-b", 1_000, true))
        assertEquals(-1, activeLyricIndex(document, "occurrence-a", 1_000, false))
    }

    @Test
    fun repeatedLineKeysCannotReachTheNativeList() {
        val document =
            JSONObject()
                .put("occurrence_id", "00000000-0000-4000-8000-000000000001")
                .put("revision", "00000000-0000-4000-8000-000000000002")
                .put("translation_source", "apple")

        fun line(
            id: String,
            start: Int,
        ) = JSONObject()
            .put("id", id)
            .put("text", "Original lyric")
            .put("translation", "English text")
            .put("start_ms", start)
            .put("end_ms", start + 1_000)
        document.put("lines", JSONArray().put(line("L1", 0)).put(line("L2", 1_000)))
        assertEquals(listOf("L1", "L2"), Wire.lyrics(document).lines.map { it.id })
        document.put("lines", JSONArray().put(line("L1", 0)).put(line("L1", 1_000)))
        assertThrows(IllegalArgumentException::class.java) { Wire.lyrics(document) }
    }

    @Test
    fun timedWordsAreParsedForPerWordHighlighting() {
        val word =
            JSONObject()
                .put("text", "Hello")
                .put("start_ms", 0)
                .put("end_ms", 400)
        val line =
            JSONObject()
                .put("id", "L1")
                .put("text", "Hello world")
                .put("start_ms", 0)
                .put("end_ms", 1_000)
                .put("words", JSONArray().put(word))
        val document =
            JSONObject()
                .put("occurrence_id", "00000000-0000-4000-8000-000000000001")
                .put("revision", "00000000-0000-4000-8000-000000000002")
                .put("translation_source", "original")
                .put("lines", JSONArray().put(line))
        val parsed = Wire.lyrics(document)
        assertEquals(
            "Hello",
            parsed.lines
                .single()
                .words
                .single()
                .text,
        )
        assertEquals(
            400,
            parsed.lines
                .single()
                .words
                .single()
                .endMs,
        )
    }
}
