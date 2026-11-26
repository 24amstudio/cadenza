package app.cadenza.remote.dream

/** Burn-in protection stages, chosen by how long the screen saver has been idle. */
enum class DreamStage {
    /** 0 to 2 minutes: blurred artwork at 16 percent, with the title, artist and active lyric line. */
    AMBIENT,

    /** 2 to 10 minutes: artwork at 8 percent, with text that drifts slowly so no pixel stays lit. */
    DRIFT,

    /** After 10 minutes: pure black with thin strokes, and no artwork or progress indicator. */
    NIGHT,
}

/** Idle time at which drift begins, and at which night mode begins. The scene waits on these same values. */
internal const val DRIFT_STARTS_MS = 2 * 60_000L
internal const val NIGHT_STARTS_MS = 10 * 60_000L

fun dreamStageFor(idleMs: Long): DreamStage =
    when {
        idleMs < DRIFT_STARTS_MS -> DreamStage.AMBIENT
        idleMs < NIGHT_STARTS_MS -> DreamStage.DRIFT
        else -> DreamStage.NIGHT
    }
