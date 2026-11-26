package app.cadenza.remote.updates

import app.cadenza.remote.data.StoredSettings

/**
 * Pauses automatic installs of one target build after [ATTEMPT_LIMIT] attempts. A signature mismatch and an install error
 * both count, so a Remote never retries the same failing APK forever. A newer build starts fresh, and a record for a build
 * that is now running is dropped.
 */
object UpdateLoopGuard {
    const val ATTEMPT_LIMIT = 2
    private const val TARGET = "loop_target_build"
    private const val ATTEMPTS = "loop_attempts"

    data class Record(
        val targetBuild: Long,
        val attempts: Int,
    )

    fun paused(
        targetBuild: Long,
        record: Record?,
    ): Boolean = record?.targetBuild == targetBuild && record.attempts >= ATTEMPT_LIMIT

    fun recordingAttempt(
        targetBuild: Long,
        record: Record?,
    ): Record =
        if (record?.targetBuild == targetBuild) {
            Record(targetBuild, record.attempts + 1)
        } else {
            Record(targetBuild, 1)
        }

    /** Keeps the record only while the installed build is still older than the target it was installing. */
    fun settled(
        record: Record?,
        installedBuild: Long,
    ): Record? = record?.takeIf { it.targetBuild > installedBuild }

    fun load(store: StoredSettings): Record? {
        val target = store.getLong(TARGET, 0)
        return if (target > 0) Record(target, store.getInt(ATTEMPTS, 0)) else null
    }

    fun save(
        store: StoredSettings,
        record: Record?,
    ) = store.write(
        TARGET to record?.targetBuild?.toString(),
        ATTEMPTS to record?.attempts?.toString(),
    )
}
