package app.cadenza.remote.ui.lyrics

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.cadenza.remote.data.LyricLine
import app.cadenza.remote.data.LyricsTextSize

// Quick start, long settle: the tier of a line eases like Cadenza Web's lyric transition.
private val lyricEase = CubicBezierEasing(0.22f, 1f, 0.36f, 1f)
private const val TIER_MS = 700
private const val COLOR_MS = 300
private const val REVEAL_MS = 320
private const val UNSUNG_MIX = 0.5f

// Room at the right edge so the scaled active line is not clipped by the list.
private val scaleRoom = 14.dp

// Lines scale about the edge they are aligned to, so an end-aligned line grows leftwards and stays flush right. A
// centred group line grows from the middle.
private val startOrigin = TransformOrigin(0f, 0.5f)
private val endOrigin = TransformOrigin(1f, 0.5f)
private val centerOrigin = TransformOrigin(0.5f, 0.5f)

// The vertical rhythm of a lyric line is 1.2x the base 14 / 6 / 8 dp: the gap between lines, the padding around a
// line, and the gap between its text and its romanization or translation. Font size is unaffected.
private const val SPACING_SCALE = 1.2f
internal val lineGap = (14f * SPACING_SCALE).dp
private val linePadding = (6f * SPACING_SCALE).dp
private val detailGap = (8f * SPACING_SCALE).dp

internal fun isEndAligned(line: LyricLine): Boolean = line.align == "end"

internal fun isCentered(line: LyricLine): Boolean = line.align == "center"

/**
 * The second singer's lines sit on the opposite edge, and a group's lines in the middle. TextAlign.End also flips for
 * right-to-left paragraphs.
 */
internal fun lyricTextAlign(line: LyricLine): TextAlign =
    when {
        isEndAligned(line) -> TextAlign.End
        isCentered(line) -> TextAlign.Center
        else -> TextAlign.Start
    }

/** How a line is drawn at the current position. Primitives only, so a line recomposes when its own state changes. */
internal data class LyricLineState(
    val tier: Float,
    val active: Boolean,
    val receding: Boolean,
    /** Whether this line is near enough to the active ones to take a blur. Others recede by opacity and scale. */
    val blur: Boolean,
    /** Energy saver: tier and colour changes switch at once instead of easing. */
    val instant: Boolean,
    val wordTimed: Boolean,
    val sweep: IntRange,
    val litWords: Int,
)

@Composable
internal fun LyricLineItem(
    line: LyricLine,
    state: LyricLineState,
    clock: LyricsClock,
    reduced: Boolean,
    translationRevealed: Boolean,
    seekable: Boolean,
    onSeek: () -> Unit,
    textSize: LyricsTextSize,
    modifier: Modifier = Modifier,
) {
    // Opacity, blur and scale all follow this one value. They are read inside the graphicsLayer lambda, so a
    // transition moves the draw phase only and never recomposes the line.
    val tier =
        animateFloatAsState(
            state.tier,
            animationSpec = if (reduced || state.instant) snap() else tween(TIER_MS, easing = lyricEase),
            label = "lyric-tier",
        )
    val end = isEndAligned(line)
    val center = isCentered(line)
    val align = lyricTextAlign(line)
    Column(
        modifier
            .fillMaxWidth()
            .graphicsLayer {
                if (!state.receding) return@graphicsLayer
                val value = tier.value
                alpha = tierOpacity(value)
                transformOrigin =
                    when {
                        end -> endOrigin
                        center -> centerOrigin
                        else -> startOrigin
                    }
                if (reduced) return@graphicsLayer
                val scale = tierScale(value)
                scaleX = scale
                scaleY = scale
                val blur = if (state.blur) tierBlurDp(value).dp.toPx() else 0f
                renderEffect = if (blur > 0.5f) BlurEffect(blur, blur, TileMode.Decal) else null
            }.clickable(enabled = seekable, role = Role.Button, onClick = onSeek)
            .padding(end = scaleRoom, top = linePadding, bottom = linePadding)
            .semantics(mergeDescendants = true) {
                selected = state.active
                if (seekable) contentDescription = "Seek to ${line.text}"
            },
        verticalArrangement = Arrangement.spacedBy(detailGap),
        horizontalAlignment =
            when {
                end -> Alignment.End
                center -> Alignment.CenterHorizontally
                else -> Alignment.Start
            },
    ) {
        LyricLineText(line, state, clock, reduced, textSize, align)
        line.romanized?.takeIf { it.isNotBlank() }?.let {
            Text(
                it,
                modifier = Modifier.fillMaxWidth(),
                style = detailTextStyle(textSize).copy(textAlign = align),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        LyricTranslation(line.translation, translationRevealed, textSize, align)
    }
}

@Composable
private fun LyricLineText(
    line: LyricLine,
    state: LyricLineState,
    clock: LyricsClock,
    reduced: Boolean,
    textSize: LyricsTextSize,
    align: TextAlign,
) {
    val colors = MaterialTheme.colorScheme
    val style = lyricTextStyle(textSize).copy(textAlign = align)
    if (state.wordTimed && line.words.isNotEmpty()) {
        LyricWordsText(
            line = line,
            sweep = state.sweep,
            litWords = state.litWords,
            clock = clock,
            bright = colors.onSurface,
            dim = lerp(colors.surface, colors.onSurface, UNSUNG_MIX),
            style = style,
            modifier = Modifier.fillMaxWidth(),
        )
        return
    }
    // Timed lines are highlighted as a whole: the active line takes the accent colour and the tiers do the rest.
    val color by animateColorAsState(
        if (state.active) colors.primary else colors.onSurface,
        animationSpec = if (reduced || state.instant) snap() else tween(COLOR_MS),
        label = "lyric-line-color",
    )
    Text(line.text, modifier = Modifier.fillMaxWidth(), style = style, color = color)
}

// The standard lyric size is 28 sp on a 390 dp screen. It follows the screen width between 24 and 32 sp, and the chosen
// multiplier applies on top, so lyrics fill a phone or a tablet without a fixed size that suits only one of them.
@Composable
private fun lyricTextStyle(size: LyricsTextSize): TextStyle {
    val density = LocalDensity.current
    val screenWidthDp = LocalWindowInfo.current.containerSize.width / density.density
    val standardSp = (screenWidthDp * 28f / 390f).coerceIn(24f, 32f)
    val fontSize = (standardSp * size.scale).sp
    return MaterialTheme.typography.headlineMedium.copy(
        fontWeight = FontWeight.Bold,
        fontSize = fontSize,
        lineHeight = fontSize * 1.22f,
    )
}

@Composable
private fun detailTextStyle(size: LyricsTextSize): TextStyle =
    MaterialTheme.typography.titleMedium.copy(
        fontSize = (16f * size.scale).sp,
        lineHeight = (24f * size.scale).sp,
    )

@Composable
private fun LyricTranslation(
    translation: String?,
    revealed: Boolean,
    textSize: LyricsTextSize,
    align: TextAlign,
) {
    AnimatedVisibility(
        visible = translation != null && revealed,
        enter =
            fadeIn(tween(REVEAL_MS, easing = lyricEase)) +
                expandVertically(tween(REVEAL_MS, easing = lyricEase), expandFrom = Alignment.Top),
        exit = fadeOut(tween(160)) + shrinkVertically(tween(160)),
    ) {
        Text(
            translation.orEmpty(),
            modifier = Modifier.fillMaxWidth(),
            style = detailTextStyle(textSize).copy(textAlign = align),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
