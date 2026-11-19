package app.cadenza.remote.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedContentScope
import androidx.compose.animation.AnimatedVisibilityScope
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionLayout
import androidx.compose.animation.SharedTransitionScope
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.IntOffset
import app.cadenza.remote.data.CurrentPlayback
import app.cadenza.remote.energy.LocalEnergyProfile
import app.cadenza.remote.ui.lyrics.rememberReducedMotion
import kotlinx.coroutines.delay

// The Now Playing surfaces share one motion language. Spatial moves (slide, shared artwork bounds) use the expressive
// spring tokens; fades use the effects tokens. System animator scale 0 turns every transition into an instant switch.

/** The song a Now Playing surface shows: its playback and its decoded artwork, which change together. */
@Immutable
internal class ShownSong(
    val current: CurrentPlayback,
    val artwork: ArtworkData?,
)

// A new song's artwork usually arrives within a few frames. Past this the surface swaps anyway, with a placeholder.
private const val ARTWORK_WAIT_MS = 700L
private const val ENTER_SLIDE_DIVISOR = 14

/**
 * The song to draw. When the song changes, the previous song stays on screen until the new one's artwork has decoded
 * (or [ARTWORK_WAIT_MS] passes), so the swap crossfades two real covers instead of flashing an empty one.
 * Updates within the same song, such as position samples, are applied at once.
 */
@Composable
internal fun rememberShownSong(current: CurrentPlayback?): ShownSong? {
    val artwork = rememberArtwork(current?.song?.artworkUrl)
    val shown = remember { mutableStateOf(current?.let { ShownSong(it, artwork) }) }
    LaunchedEffect(current, artwork) {
        val showing = shown.value
        when {
            current == null -> shown.value = null
            showing == null || showing.current.occurrenceId == current.occurrenceId ->
                shown.value = ShownSong(current, artwork ?: showing?.artwork)
            artwork != null || current.song.artworkUrl == null -> shown.value = ShownSong(current, artwork)
            else -> {
                delay(ARTWORK_WAIT_MS)
                shown.value = ShownSong(current, null)
            }
        }
    }
    // The first frame of a new song, before the effect has run, shows it as it is.
    return shown.value ?: current?.let { ShownSong(it, artwork) }
}

/**
 * Crossfades [target]'s content with a short upward drift when the song changes. Only [occurrenceOf] keys the
 * transition, so position and queue updates for the same song never retrigger it.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun <T> SongSwap(
    target: T,
    occurrenceOf: (T) -> String,
    modifier: Modifier = Modifier,
    content: @Composable (T) -> Unit,
) {
    val reduced = rememberReducedMotion() || LocalEnergyProfile.current.reduceTransitions
    val spatial = MaterialTheme.motionScheme.defaultSpatialSpec<IntOffset>()
    val enter = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val exit = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    AnimatedContent(
        targetState = target,
        modifier = modifier,
        contentKey = occurrenceOf,
        transitionSpec = {
            if (reduced) {
                fadeIn(snap()) togetherWith fadeOut(snap())
            } else {
                (fadeIn(enter) + slideInVertically(spatial) { it / ENTER_SLIDE_DIVISOR }) togetherWith fadeOut(exit)
            }.using(SizeTransform(clip = false) { _, _ -> snap() })
        },
        label = "now-playing-song",
    ) { shown ->
        content(shown)
    }
}

/**
 * A backdrop whose top colour follows the artwork accent. The colour eases when the song changes, so the screen never
 * blinks between two covers.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun rememberBackdrop(
    accent: Color?,
    accentAlpha: Float,
    fallbackTop: Color,
): Brush {
    val reduced = rememberReducedMotion() || LocalEnergyProfile.current.reduceTransitions
    val surface = MaterialTheme.colorScheme.surface
    val top by animateColorAsState(
        targetValue = accent?.copy(alpha = accentAlpha) ?: fallbackTop,
        animationSpec = if (reduced) snap() else MaterialTheme.motionScheme.slowEffectsSpec(),
        label = "now-playing-backdrop",
    )
    return Brush.verticalGradient(listOf(top, surface.copy(alpha = 0.95f), surface))
}

/** The full-screen surfaces that cross-animate: the tabs, the Now Playing screen and the lyrics. */
internal enum class Surface { Main, NowPlaying, Lyrics }

internal fun surfaceOf(
    paired: Boolean,
    lyricsMode: Boolean,
    nowPlayingOpen: Boolean,
): Surface =
    when {
        paired && lyricsMode -> Surface.Lyrics
        paired && nowPlayingOpen -> Surface.NowPlaying
        else -> Surface.Main
    }

@OptIn(ExperimentalSharedTransitionApi::class)
internal class SurfaceTransition(
    val shared: SharedTransitionScope,
    val visibility: AnimatedVisibilityScope,
)

internal val LocalSurfaceTransition = staticCompositionLocalOf<SurfaceTransition?> { null }

/**
 * Hosts the surfaces so switching between them is one coordinated transition: the surfaces fade through each other
 * while the artwork, which every surface shows, travels between its bounds (see [sharedArtwork]).
 */
@OptIn(ExperimentalSharedTransitionApi::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun SurfaceHost(
    surface: Surface,
    modifier: Modifier = Modifier,
    content: @Composable AnimatedContentScope.(Surface) -> Unit,
) {
    val reduced = rememberReducedMotion() || LocalEnergyProfile.current.reduceTransitions
    val enter = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val exit = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    SharedTransitionLayout(modifier) {
        AnimatedContent(
            targetState = surface,
            modifier = Modifier,
            transitionSpec = {
                if (reduced) {
                    fadeIn(snap()) togetherWith fadeOut(snap())
                } else {
                    fadeIn(enter) togetherWith fadeOut(exit)
                }.using(SizeTransform(clip = false) { _, _ -> snap() })
            },
            label = "now-playing-surface",
        ) { target ->
            val transition = remember(this@SharedTransitionLayout, this) { SurfaceTransition(this@SharedTransitionLayout, this) }
            CompositionLocalProvider(LocalSurfaceTransition provides transition.takeUnless { reduced }) {
                content(target)
            }
        }
    }
}

/**
 * Marks the cover of [occurrenceId] as shared between surfaces. The key includes the occurrence so a song change
 * inside one surface never has two covers with the same key.
 */
@OptIn(ExperimentalSharedTransitionApi::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun Modifier.sharedArtwork(occurrenceId: String): Modifier {
    val transition = LocalSurfaceTransition.current ?: return this
    val bounds = MaterialTheme.motionScheme.defaultSpatialSpec<Rect>()
    return with(transition.shared) {
        this@sharedArtwork.sharedElement(
            sharedContentState = rememberSharedContentState("artwork:$occurrenceId"),
            animatedVisibilityScope = transition.visibility,
            boundsTransform = { _, _ -> bounds },
        )
    }
}
