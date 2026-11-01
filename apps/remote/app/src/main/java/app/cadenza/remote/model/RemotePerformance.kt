package app.cadenza.remote.model

import android.os.SystemClock

private const val SLOW_COMPONENT_THRESHOLD_MS = 16L

internal suspend fun <T> RemoteModel.measureComponent(
    component: String,
    block: suspend () -> T,
): T {
    val startedAt = SystemClock.elapsedRealtime()
    return try {
        block()
    } finally {
        recordComponentDuration(component, SystemClock.elapsedRealtime() - startedAt)
    }
}

internal fun RemoteModel.recordComponentDuration(
    component: String,
    durationMs: Long,
    details: String = "",
    minimumDurationMs: Long = SLOW_COMPONENT_THRESHOLD_MS,
) {
    if (durationMs < minimumDurationMs) return
    val suffix = if (details.isBlank()) "" else " $details"
    reportLog("info", "performance.component", "component=$component duration_ms=$durationMs$suffix")
}

internal fun RemoteModel.recordLyricsDuration() {
    val startedAt = lyricStartedAtElapsedMs ?: return
    lyricStartedAtElapsedMs = null
    recordComponentDuration(
        "lyrics",
        (SystemClock.elapsedRealtime() - startedAt).coerceAtLeast(0),
        minimumDurationMs = 0,
    )
}
