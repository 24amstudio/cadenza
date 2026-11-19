package app.cadenza.remote.ui.lyrics

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import kotlinx.coroutines.flow.first
import kotlin.math.abs

private const val FOLLOW_MS = 850
private val followEase = CubicBezierEasing(0.25f, 1f, 0.5f, 1f)

/** What the last centring saw, so only a change of the same viewport animates. Touched from the follow effect only. */
private class FollowProgress {
    var centered = false
    var viewportHeight = 0
}

/**
 * Keeps [anchor], the newest active line, centred in the viewport. The first centring after the lyrics open (and any
 * after a viewport resize) is instant, so the current line is in place without a manual scroll. Later ones glide.
 * Reduced motion makes every centring instant. The effect restarts, cancelling a glide in flight, when the anchor,
 * document, viewport or following flag changes, and [following] false (the user scrolled) stops it.
 */
@Composable
internal fun FollowActiveLine(
    list: LazyListState,
    anchor: Int,
    revision: String?,
    following: Boolean,
    reduced: Boolean,
) {
    val progress = remember(list) { FollowProgress() }
    val viewportHeight by remember(list) { derivedStateOf { list.layoutInfo.viewportSize.height } }
    LaunchedEffect(anchor, revision, following, viewportHeight, reduced) {
        if (!following || anchor < 0) return@LaunchedEffect
        snapshotFlow { list.layoutInfo.viewportSize.height > 0 && list.layoutInfo.totalItemsCount > anchor }.first { it }
        val glide = !reduced && progress.centered && progress.viewportHeight == viewportHeight
        list.centerItem(anchor, glide)
        progress.centered = true
        progress.viewportHeight = viewportHeight
    }
}

/**
 * Centres [index] on the middle of the viewport. An item off screen is first brought into the layout, since its size is
 * unknown until it is measured, and then centred without a glide.
 */
private suspend fun LazyListState.centerItem(
    index: Int,
    glide: Boolean,
) {
    var item = layoutInfo.visibleItemsInfo.firstOrNull { it.index == index }
    val visibleBefore = item != null
    if (item == null) {
        scrollToItem(index)
        withFrameNanos { }
        item = layoutInfo.visibleItemsInfo.firstOrNull { it.index == index } ?: return
    }
    val viewportCenter = (layoutInfo.viewportStartOffset + layoutInfo.viewportEndOffset) / 2f
    val delta = item.offset + item.size / 2f - viewportCenter
    if (abs(delta) < 1f) return
    if (glide && visibleBefore) animateScrollBy(delta, tween(FOLLOW_MS, easing = followEase)) else scrollBy(delta)
}

/** Reports a finger or fling that scrolls the list, as opposed to the follow effect's own scrolling. */
@Composable
internal fun rememberUserScrollConnection(onUserScroll: () -> Unit): NestedScrollConnection {
    val latest by rememberUpdatedState(onUserScroll)
    return remember {
        object : NestedScrollConnection {
            override fun onPreScroll(
                available: Offset,
                source: NestedScrollSource,
            ): Offset {
                if (source == NestedScrollSource.UserInput && available.y != 0f) latest()
                return Offset.Zero
            }
        }
    }
}
