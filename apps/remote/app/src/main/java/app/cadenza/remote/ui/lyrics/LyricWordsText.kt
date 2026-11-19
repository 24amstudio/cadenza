package app.cadenza.remote.ui.lyrics

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.ResolvedTextDirection
import app.cadenza.remote.data.LyricLine
import app.cadenza.remote.data.LyricWord

/** Character ranges of each word inside the joined line text, without the whitespace Hosts attach to words. */
private class WordSpans(
    words: List<LyricWord>,
) {
    val text: String = words.joinToString("") { it.text }
    private val starts = IntArray(words.size + 1)
    private val trimmedStarts = IntArray(words.size)
    private val trimmedEnds = IntArray(words.size)

    init {
        var offset = 0
        words.forEachIndexed { index, word ->
            val raw = word.text
            starts[index] = offset
            trimmedStarts[index] = offset + raw.length - raw.trimStart().length
            trimmedEnds[index] = offset + raw.trimEnd().length
            offset += raw.length
        }
        starts[words.size] = offset
    }

    /** Offset of the first character of [word]; the line length for the index one past the last word. */
    fun start(word: Int): Int = starts[word.coerceIn(0, starts.size - 1)]

    fun glyphStart(word: Int): Int = trimmedStarts[word]

    fun glyphEnd(word: Int): Int = trimmedEnds[word]
}

/** Bounds of each word in the latest text layout. They are computed once per word and layout, not once per frame. */
private class WordMeasure(
    private val spans: WordSpans,
    wordCount: Int,
) {
    var layout: TextLayoutResult? = null
    private var boundsLayout: TextLayoutResult? = null
    private val measured = BooleanArray(wordCount)
    private val bounds = arrayOfNulls<Rect>(wordCount)
    private val rightToLeft = BooleanArray(wordCount)

    fun boundsOf(word: Int): Rect? {
        val current = layout ?: return null
        if (current !== boundsLayout) {
            boundsLayout = current
            measured.fill(false)
        }
        if (!measured[word]) {
            measured[word] = true
            val start = spans.glyphStart(word)
            val end = spans.glyphEnd(word)
            bounds[word] = if (end > start) current.getPathForRange(start, end).getBounds() else null
            rightToLeft[word] = end > start && current.getBidiRunDirection(start) == ResolvedTextDirection.Rtl
        }
        return bounds[word]
    }

    fun isRightToLeft(word: Int): Boolean = rightToLeft[word]
}

/**
 * A word-timed lyric line as one paragraph, so wrapping and syllables behave like ordinary text. Sung words are
 * [bright]; the rest are [dim]. Every word in [sweep], the words sounding now, is bright in the text and its unsung
 * part is covered in the draw phase by a [dim] gradient with a soft edge, composited over the glyphs only. Several
 * words, in this line or in overlapping lines, each take their own fill from their own timing. That draw reads
 * [LyricsClock.liveMs], so a frame redraws these lines and recomposes nothing.
 */
@Composable
internal fun LyricWordsText(
    line: LyricLine,
    sweep: IntRange,
    litWords: Int,
    clock: LyricsClock,
    bright: Color,
    dim: Color,
    style: TextStyle,
    modifier: Modifier = Modifier,
) {
    val spans = remember(line.words) { WordSpans(line.words) }
    val measure = remember(spans) { WordMeasure(spans, line.words.size) }
    val litThrough = if (sweep.isEmpty()) litWords else sweep.last + 1
    val text: AnnotatedString =
        remember(spans, litThrough, bright) {
            buildAnnotatedString {
                append(spans.text)
                val lit = spans.start(litThrough)
                if (lit > 0) addStyle(SpanStyle(color = bright), 0, lit)
            }
        }
    val overlay =
        if (sweep.isEmpty()) {
            Modifier
        } else {
            Modifier
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    val positionMs = clock.liveMs()
                    for (index in sweep) {
                        val word = line.words.getOrNull(index) ?: continue
                        val fill = wordFill(word, positionMs)
                        drawUnsungMask(measure.boundsOf(index), measure.isRightToLeft(index), fill, sweepEdgeFraction(fill), dim)
                    }
                }
        }
    Text(
        text = text,
        modifier = modifier.then(overlay),
        color = dim,
        style = style,
        onTextLayout = { measure.layout = it },
    )
}

// SrcAtop paints only where the layer already has glyph pixels, so the dim gradient recolours the unsung part of
// the word without touching its neighbours or the background. The two colour stops share dim's RGB, so the edge
// blends from bright to dim without a dark fringe.
private fun DrawScope.drawUnsungMask(
    bounds: Rect?,
    rightToLeft: Boolean,
    fill: Float,
    edge: Float,
    dim: Color,
) {
    if (bounds == null || fill >= 1f) return
    val clear = dim.copy(alpha = 0f)
    val low = (fill - edge).coerceIn(0f, 1f)
    val high = (fill + edge).coerceIn(low, 1f)
    val brush =
        Brush.horizontalGradient(
            0f to clear,
            low to clear,
            high to dim,
            1f to dim,
            startX = if (rightToLeft) bounds.right else bounds.left,
            endX = if (rightToLeft) bounds.left else bounds.right,
        )
    drawRect(brush, topLeft = bounds.topLeft, size = bounds.size, blendMode = BlendMode.SrcAtop)
}
