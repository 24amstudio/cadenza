package app.cadenza.remote.ui.lyrics

import app.cadenza.remote.data.LyricLine
import app.cadenza.remote.data.LyricWord
import kotlin.math.abs

// Pure lyric timing rules shared by the line list and the word sweep. They mirror Cadenza Web's
// lyrics helpers so both Remotes highlight the same line and word at the same position.

/**
 * Every line sounding at [positionMs] is active, because background vocals are timed as separate
 * lines that overlap their main line. Provider end markers can leave short gaps between lines; then
 * the most recently started line stays active so highlighting and following never drop out.
 */
internal fun activeLineIndices(
    lines: List<LyricLine>,
    positionMs: Long,
): List<Int> {
    val sounding = ArrayList<Int>(2)
    var latest = -1
    for (index in lines.indices) {
        val line = lines[index]
        if (line.endMs <= line.startMs || line.startMs > positionMs) continue
        latest = index
        if (positionMs < line.endMs) sounding += index
    }
    return when {
        sounding.isNotEmpty() -> sounding
        latest >= 0 -> listOf(latest)
        else -> emptyList()
    }
}

/** The newest active line, or -1. Equals the last of [activeLineIndices] without allocating a list. */
internal fun newestActiveLine(
    lines: List<LyricLine>,
    positionMs: Long,
): Int {
    var latest = -1
    var newestSounding = -1
    for (index in lines.indices) {
        val line = lines[index]
        if (line.endMs <= line.startMs || line.startMs > positionMs) continue
        latest = index
        if (positionMs < line.endMs) newestSounding = index
    }
    return if (newestSounding >= 0) newestSounding else latest
}

/** Fill of one word from 0 (not started) to 1 (finished). */
internal fun wordFill(
    word: LyricWord,
    positionMs: Long,
): Float =
    when {
        positionMs <= word.startMs -> 0f
        positionMs >= word.endMs -> 1f
        else -> (positionMs - word.startMs).toFloat() / (word.endMs - word.startMs)
    }

// Provider timings can overlap, so an earlier word may still be ending when the next one starts.
internal fun latestStartedWord(
    words: List<LyricWord>,
    positionMs: Long,
): Int = words.indexOfLast { it.endMs > it.startMs && it.startMs <= positionMs }

/**
 * Fill for each word of [line]. Only one word sweeps at a time: the latest started word of the sweeping
 * line. Earlier words are sung and later ones are not. Every other line shows whole words.
 */
internal fun wordFills(
    line: LyricLine,
    positionMs: Long,
    sweeping: Boolean,
): FloatArray {
    val latest = latestStartedWord(line.words, positionMs)
    return FloatArray(line.words.size) { index ->
        when {
            !sweeping -> if (line.words[index].startMs <= positionMs) 1f else 0f
            index == latest -> wordFill(line.words[index], positionMs)
            index < latest -> 1f
            else -> 0f
        }
    }
}

/** Number of leading words that have started. Lines that do not sweep show exactly these words lit. */
internal fun litWordCount(
    words: List<LyricWord>,
    positionMs: Long,
): Int = words.indexOfLast { it.startMs <= positionMs } + 1

internal data class SweepTarget(
    val line: Int,
    val word: Int,
)

/**
 * The one word that sweeps across all lines: the latest started word of the newest sounding line, or
 * null before that line's first word starts. Overlapping lines do not add sweeps.
 */
internal fun sweepTarget(
    lines: List<LyricLine>,
    positionMs: Long,
): SweepTarget? {
    val line = newestActiveLine(lines, positionMs)
    if (line < 0) return null
    val word = latestStartedWord(lines[line].words, positionMs)
    return if (word < 0) null else SweepTarget(line, word)
}

private const val SWEEP_EDGE_FRACTION = 0.12f

/**
 * Half-width of the soft edge on the sweeping word, as a fraction of the word. It is widest halfway
 * through the word and zero at both ends, so a word that has not started or has finished has a hard edge.
 */
internal fun sweepEdgeFraction(fill: Float): Float = SWEEP_EDGE_FRACTION * (1f - abs(fill * 2f - 1f))
