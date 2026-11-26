package app.cadenza.remote.media

import app.cadenza.remote.data.LyricLine
import app.cadenza.remote.ui.lyrics.activeLineIndices

/**
 * The line the notification shows as subtext. Null when the screen is off, no timed line is sounding, or the song has no
 * timed lyrics, so the notification then keeps its artist text.
 */
internal fun lyricSubtext(
    lines: List<LyricLine>?,
    positionMs: Long,
    screenInteractive: Boolean,
): String? {
    if (!screenInteractive || lines == null) return null
    val index = activeLineIndices(lines, positionMs).firstOrNull() ?: return null
    return lines[index].text.takeIf { it.isNotBlank() }
}

/** The next moment a line starts or ends after [positionMs], or null when there is none. Used to wake only at changes. */
internal fun nextLyricChangeMs(
    lines: List<LyricLine>?,
    positionMs: Long,
): Long? =
    lines
        ?.flatMap { listOf(it.startMs, it.endMs) }
        ?.filter { it > positionMs }
        ?.minOrNull()
