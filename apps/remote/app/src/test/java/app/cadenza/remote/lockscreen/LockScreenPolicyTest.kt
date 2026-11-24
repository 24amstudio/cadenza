package app.cadenza.remote.lockscreen

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LockScreenPolicyTest {
    @Test
    fun opensOnlyForPlayingMotionArtworkWithTheScreenOff() {
        assertTrue(LockScreenPolicy.shouldOpen(true, true, playing = true, connected = true, screenOff = true))
        assertFalse(LockScreenPolicy.shouldOpen(false, true, playing = true, connected = true, screenOff = true))
        assertFalse(LockScreenPolicy.shouldOpen(true, false, playing = true, connected = true, screenOff = true))
        assertFalse(LockScreenPolicy.shouldOpen(true, true, playing = false, connected = true, screenOff = true))
        assertFalse(LockScreenPolicy.shouldOpen(true, true, playing = true, connected = true, screenOff = false))
    }

    @Test
    fun closesOnUnlockPauseOrDisconnect() {
        assertTrue(LockScreenPolicy.shouldClose(playing = true, connected = true, userPresent = true))
        assertTrue(LockScreenPolicy.shouldClose(playing = false, connected = true, userPresent = false))
        assertTrue(LockScreenPolicy.shouldClose(playing = true, connected = false, userPresent = false))
        assertFalse(LockScreenPolicy.shouldClose(playing = true, connected = true, userPresent = false))
    }
}
