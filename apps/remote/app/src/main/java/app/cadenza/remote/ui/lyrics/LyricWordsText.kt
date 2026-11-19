package app.cadenza.remote.ui.lyrics

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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

/** Bounds of a word in the latest text layout. They are computed once per word, not once per frame. */
private class WordMeasure(
    private val spans: WordSpans,
) {
    var layout: TextLayoutResult? = null
    private var boundsLayout: TextLayoutResult? = null
    private var boundsWord = -1
    private var bounds: Rect? = null
    var rightToLeft = false
        private set

    fun boundsOf(word: Int): Rect? {
        val current = layout ?: return null
        if (current !== boundsLayout || word != boundsWord) {
            boundsLayout = current
            boundsWord = word
            val start = spans.glyphStart(word)
            val end = spans.glyphEnd(word)
            bounds = if (end > start) current.getPathForRange(start, end).getBounds() else null
            rightToLeft = end > start && current.getBidiRunDirection(start) == ResolvedTextDirection.Rtl
        }
        return bounds
    }
}

private class SweepTracker {
    var word = -1
}

private const val FINISH_MS = 150

/**
 * A word-timed lyric line as one paragraph, so wrapping and syllables behave like ordinary text. Sung words are
 * [bright]; the rest are [dim]. The sweeping word is bright in the text and its unsung part is covered in the
 * draw phase by a [dim] gradient with a soft edge, composited over the glyphs only. That draw reads
 * [LyricsClock.liveMs], so a frame redraws this one line and recomposes nothing.
 */
@Composable
internal fun LyricWordsText(
    line: LyricLine,
    sweepWord: Int,
    litWords: Int,
    clock: LyricsClock,
    bright: Color,
    dim: Color,
    style: TextStyle,
    animateFinish: Boolean,
    modifier: Modifier = Modifier,
) {
    val spans = remember(line.words) { WordSpans(line.words) }
    val measure = remember(spans) { WordMeasure(spans) }
    val litThrough = if (sweepWord >= 0) sweepWord + 1 else litWords
    val text: AnnotatedString =
        remember(spans, litThrough, bright) {
            buildAnnotatedString {
                append(spans.text)
                val lit = spans.start(litThrough)
                if (lit > 0) addStyle(SpanStyle(color = bright), 0, lit)
            }
        }

    // The word that stops sweeping finishes over a short ease so a handoff between overlapping lines does not snap.
    val finishFill = remember { Animatable(1f) }
    var finishingWord by remember { mutableIntStateOf(-1) }
    val tracker = remember { SweepTracker() }
    LaunchedEffect(sweepWord, animateFinish) {
        val ended = tracker.word
        tracker.word = sweepWord
        val word = line.words.getOrNull(ended)
        if (word == null || ended == sweepWord || !animateFinish) return@LaunchedEffect
        val from = wordFill(word, clock.liveMs())
        if (from <= 0f || from >= 1f) return@LaunchedEffect
        finishingWord = ended
        try {
            finishFill.snapTo(from)
            finishFill.animateTo(1f, tween(FINISH_MS, easing = LinearOutSlowInEasing))
        } finally {
            finishingWord = -1
        }
    }

    val overlay =
        if (sweepWord >= 0 || finishingWord >= 0) {
            Modifier
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    if (finishingWord >= 0 && finishingWord != sweepWord) {
                        drawUnsungMask(measure.boundsOf(finishingWord), measure.rightToLeft, finishFill.value, 0f, dim)
                    }
                    val sweeping = line.words.getOrNull(sweepWord)
                    if (sweeping != null) {
                        val fill = wordFill(sweeping, clock.liveMs())
                        drawUnsungMask(measure.boundsOf(sweepWord), measure.rightToLeft, fill, sweepEdgeFraction(fill), dim)
                    }
                }
        } else {
            Modifier
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
