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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.LyricLine

// Quick start, long settle: the tier of a line eases like Cadenza Web's lyric transition.
private val lyricEase = CubicBezierEasing(0.22f, 1f, 0.36f, 1f)
private const val TIER_MS = 700
private const val COLOR_MS = 300
private const val REVEAL_MS = 320
private const val UNSUNG_MIX = 0.5f

// Room at the right edge so the scaled active line is not clipped by the list.
private val scaleRoom = 14.dp
private val lineOrigin = TransformOrigin(0f, 0.5f)

/** How a line is drawn at the current position. Primitives only, so a line recomposes when its own state changes. */
internal data class LyricLineState(
    val tier: Float,
    val active: Boolean,
    val receding: Boolean,
    val wordTimed: Boolean,
    val sweepWord: Int,
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
    modifier: Modifier = Modifier,
) {
    // Opacity, blur and scale all follow this one value. They are read inside the graphicsLayer lambda, so a
    // transition moves the draw phase only and never recomposes the line.
    val tier =
        animateFloatAsState(
            state.tier,
            animationSpec = if (reduced) snap() else tween(TIER_MS, easing = lyricEase),
            label = "lyric-tier",
        )
    Column(
        modifier
            .fillMaxWidth()
            .graphicsLayer {
                if (!state.receding) return@graphicsLayer
                val value = tier.value
                alpha = tierOpacity(value)
                transformOrigin = lineOrigin
                if (reduced) return@graphicsLayer
                val scale = tierScale(value)
                scaleX = scale
                scaleY = scale
                val blur = tierBlurDp(value).dp.toPx()
                renderEffect = if (blur > 0.5f) BlurEffect(blur, blur, TileMode.Decal) else null
            }.clickable(enabled = seekable, role = Role.Button, onClick = onSeek)
            .padding(end = scaleRoom, top = 6.dp, bottom = 6.dp)
            .semantics(mergeDescendants = true) {
                selected = state.active
                if (seekable) contentDescription = "Seek to ${line.text}"
            },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        LyricLineText(line, state, clock, reduced)
        line.romanized?.takeIf { it.isNotBlank() }?.let {
            Text(it, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        LyricTranslation(line.translation, translationRevealed)
    }
}

@Composable
private fun LyricLineText(
    line: LyricLine,
    state: LyricLineState,
    clock: LyricsClock,
    reduced: Boolean,
) {
    val colors = MaterialTheme.colorScheme
    val style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold)
    if (state.wordTimed && line.words.isNotEmpty()) {
        LyricWordsText(
            line = line,
            sweepWord = state.sweepWord,
            litWords = state.litWords,
            clock = clock,
            bright = colors.onSurface,
            dim = lerp(colors.surface, colors.onSurface, UNSUNG_MIX),
            style = style,
            animateFinish = !reduced,
        )
        return
    }
    // Timed lines are highlighted as a whole: the active line takes the accent colour and the tiers do the rest.
    val color by animateColorAsState(
        if (state.active) colors.primary else colors.onSurface,
        animationSpec = if (reduced) snap() else tween(COLOR_MS),
        label = "lyric-line-color",
    )
    Text(line.text, style = style, color = color)
}

@Composable
private fun LyricTranslation(
    translation: String?,
    revealed: Boolean,
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
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
