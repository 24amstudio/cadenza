package app.cadenza.remote.ui.lyrics

import kotlin.math.abs

// A line's tier is its distance from the nearest active line: 0 active, 1 next to it, 2 and beyond far.
// The tier eases as one value, and opacity, blur and scale all derive from it, so a line that changes
// tier mid-transition keeps a single running animation.
internal const val TIER_ACTIVE = 0f
internal const val TIER_NEAR = 1f
internal const val TIER_FAR = 2f

internal fun lyricTier(
    index: Int,
    active: List<Int>,
): Float {
    // Before the first line starts, upcoming lines stay readable instead of fading to the far tier.
    if (active.isEmpty()) return TIER_NEAR
    val distance = active.minOf { abs(index - it) }
    return distance.coerceAtMost(TIER_FAR.toInt()).toFloat()
}

/**
 * Whether a receding line is close enough to the active lines to deserve a blur. Lines past [blurLines] are already
 * faint, so they recede by opacity alone and the GPU blurs only the few lines that are readable. Before the first line
 * starts, the opening lines count as near.
 */
internal fun inBlurWindow(
    index: Int,
    active: List<Int>,
    blurLines: Int,
): Boolean =
    when {
        blurLines <= 0 -> false
        active.isEmpty() -> index < blurLines
        else -> active.any { abs(index - it) <= blurLines }
    }

private fun tierValue(
    tier: Float,
    active: Float,
    near: Float,
    far: Float,
): Float =
    if (tier <= TIER_NEAR) {
        active + (near - active) * tier.coerceAtLeast(TIER_ACTIVE)
    } else {
        near + (far - near) * (tier - TIER_NEAR).coerceAtMost(TIER_NEAR)
    }

internal fun tierOpacity(tier: Float): Float = tierValue(tier, 1f, 0.55f, 0.3f)

internal fun tierBlurDp(tier: Float): Float = tierValue(tier, 0f, 2f, 4f)

internal fun tierScale(tier: Float): Float = tierValue(tier, 1.04f, 0.985f, 0.96f)
