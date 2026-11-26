package app.cadenza.remote.widget

/** One lyric line for the widget. [end] lines belong to a second singer and are drawn on the trailing edge. */
data class WidgetLyric(
    val text: String,
    val end: Boolean,
)

/** Three lines centered on the active line. Index [ACTIVE] is the active line, and [ACTIVE] + 1 is the one after it. */
internal const val LYRIC_WINDOW = 3
internal const val ACTIVE = 1

private val blank = WidgetLyric(text = "", end = false)

/** Lines around [activeIndex], padded with blanks at the song's edges. A null index yields an empty window. */
internal fun lyricWindow(
    lines: List<WidgetLyric>,
    activeIndex: Int?,
): List<WidgetLyric> {
    if (activeIndex == null || activeIndex !in lines.indices) return List(LYRIC_WINDOW) { blank }
    return List(LYRIC_WINDOW) { offset -> lines.getOrElse(activeIndex - ACTIVE + offset) { blank } }
}
