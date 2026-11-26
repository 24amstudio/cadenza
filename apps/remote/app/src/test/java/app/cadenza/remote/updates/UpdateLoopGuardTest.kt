package app.cadenza.remote.updates

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateLoopGuardTest {
    @Test
    fun aBuildThatFailedTwiceIsPausedUntilANewerBuildAppears() {
        val first = UpdateLoopGuard.recordingAttempt(12, record = null)
        val second = UpdateLoopGuard.recordingAttempt(12, first)

        assertFalse(UpdateLoopGuard.paused(12, first))
        assertTrue(UpdateLoopGuard.paused(12, second))
        assertFalse(UpdateLoopGuard.paused(13, second))
        assertEquals(UpdateLoopGuard.Record(13, 1), UpdateLoopGuard.recordingAttempt(13, second))
    }

    @Test
    fun aRecordIsDroppedOnceItsBuildIsRunning() {
        val record = UpdateLoopGuard.Record(12, attempts = 1)

        assertNull(UpdateLoopGuard.settled(record, installedBuild = 12))
        assertEquals(record, UpdateLoopGuard.settled(record, installedBuild = 11))
    }
}
