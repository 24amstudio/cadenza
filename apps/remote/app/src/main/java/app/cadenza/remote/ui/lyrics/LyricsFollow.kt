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

/** Lines kept visible above the active one. Everything older scrolls out of the top of the viewport. */
internal const val LEAD_LINES = 2

/** Where line 0 rests, as a share of the viewport height, until two lines precede the active one. */
internal const val LEAD_REST_FRACTION = 0.14f

/** The active line never sits lower than this share of the viewport, however tall the lines above it are. */
internal const val ANCHOR_MAX_FRACTION = 0.4f

/** Space after the last line, so the closing lines can still rise to the follow position. */
internal const val END_PAD_FRACTION = 0.6f

/**
 * Scroll distance (positive scrolls the content up) that puts the active line [anchorTop] near the top of the
 * viewport, [LEAD_LINES] lines below it. [leadTop] is the top of the first of those lines. Both are measured from the
 * viewport top. [restPx] is where that first line stays before two lines precede the active one: the list's top
 * padding for the first lines, 0 afterwards, so the opening lines do not jump. When the lines above are tall the
 * active line is held at [ANCHOR_MAX_FRACTION] of the viewport and the first of them is partly scrolled out.
 */
internal fun leadAlignDelta(
    leadTop: Float,
    anchorTop: Float,
    viewportHeight: Float,
    restPx: Float,
): Float {
    val span = anchorTop - leadTop
    val desiredLeadTop = minOf(restPx, viewportHeight * ANCHOR_MAX_FRACTION - span)
    return leadTop - desiredLeadTop
}

/** What the last alignment saw, so only a change of the same viewport animates. Touched from the follow effect only. */
private class FollowProgress {
    var aligned = false
    var viewportHeight = 0
}

/**
 * Keeps [anchor], the oldest active line, near the top of the viewport with [LEAD_LINES] lines above it. The first
 * alignment after the lyrics open (and any after a viewport resize) is instant, so the current line is in place without
 * a manual scroll. Later ones glide. Reduced motion makes every alignment instant. The effect restarts, cancelling a
 * glide in flight, when the anchor, document, viewport or following flag changes, and [following] false (the user
 * scrolled) stops it.
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
        val glide = !reduced && progress.aligned && progress.viewportHeight == viewportHeight
        list.alignAnchor(anchor, glide)
        progress.aligned = true
        progress.viewportHeight = viewportHeight
    }
}

private fun LazyListState.alignDelta(
    lead: Int,
    anchor: Int,
): Float? {
    val info = layoutInfo
    val leadItem = info.visibleItemsInfo.firstOrNull { it.index == lead } ?: return null
    val anchorItem = info.visibleItemsInfo.firstOrNull { it.index == anchor } ?: return null
    val rest = if (anchor < LEAD_LINES) info.beforeContentPadding.toFloat() else 0f
    return leadAlignDelta(
        leadTop = (leadItem.offset - info.viewportStartOffset).toFloat(),
        anchorTop = (anchorItem.offset - info.viewportStartOffset).toFloat(),
        viewportHeight = info.viewportSize.height.toFloat(),
        restPx = rest,
    )
}

/**
 * Scrolls [anchor] into its follow position. Lines off screen are first brought into the layout, since their size is
 * unknown until they are measured, and then aligned without a glide.
 */
private suspend fun LazyListState.alignAnchor(
    anchor: Int,
    glide: Boolean,
) {
    val lead = (anchor - LEAD_LINES).coerceAtLeast(0)
    var delta = alignDelta(lead, anchor)
    val visibleBefore = delta != null
    if (delta == null) {
        scrollToItem(lead)
        withFrameNanos { }
        delta = alignDelta(lead, anchor) ?: return
    }
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
