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

/** Number of leading words that have started. Lines that do not sweep show exactly these words lit. */
internal fun litWordCount(
    words: List<LyricWord>,
    positionMs: Long,
): Int = words.indexOfLast { it.startMs <= positionMs } + 1

/** Sounding words of each line that sweeps now, keyed by line index. Lines with no sounding word are absent. */
internal typealias Sweeps = Map<Int, IntRange>

/**
 * First through last word of [words] that sounds at [positionMs], or an empty range. Provider word timings overlap,
 * so more than one word of a line can sound at once. Words between the two ends stay lit by the line's lit prefix.
 */
internal fun soundingWords(
    words: List<LyricWord>,
    positionMs: Long,
): IntRange {
    var first = -1
    var last = -1
    for (index in words.indices) {
        val word = words[index]
        if (word.endMs <= word.startMs || positionMs < word.startMs || positionMs >= word.endMs) continue
        if (first < 0) first = index
        last = index
    }
    return if (first < 0) IntRange.EMPTY else first..last
}

/**
 * Every sounding word of every line, so overlapping lines (background vocals, duets) and overlapping words each
 * sweep from their own timing. Lines that ended, have not started or carry no words are skipped without a word scan.
 */
internal fun sweepTargets(
    lines: List<LyricLine>,
    positionMs: Long,
): Sweeps {
    var sweeps: HashMap<Int, IntRange>? = null
    for (index in lines.indices) {
        val line = lines[index]
        val lastWord = line.words.lastOrNull() ?: continue
        if (positionMs < line.startMs || positionMs >= maxOf(line.endMs, lastWord.endMs)) continue
        val sounding = soundingWords(line.words, positionMs)
        if (sounding.isEmpty()) continue
        val target = sweeps ?: HashMap<Int, IntRange>(4).also { sweeps = it }
        target[index] = sounding
    }
    return sweeps ?: emptyMap()
}

private const val SWEEP_EDGE_FRACTION = 0.12f

/**
 * Half-width of the soft edge on the sweeping word, as a fraction of the word. It is widest halfway
 * through the word and zero at both ends, so a word that has not started or has finished has a hard edge.
 */
internal fun sweepEdgeFraction(fill: Float): Float = SWEEP_EDGE_FRACTION * (1f - abs(fill * 2f - 1f))
