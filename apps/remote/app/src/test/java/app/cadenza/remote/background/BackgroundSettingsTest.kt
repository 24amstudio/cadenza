package app.cadenza.remote.background

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BackgroundSettingsTest {
    @Test
    fun harmonyOsAndEmuiDevicesKeepSilentPlaybackOnByDefault() {
        assertTrue(silentKeepAliveDefault("HUAWEI"))
        assertTrue(silentKeepAliveDefault("honor"))
        assertFalse(silentKeepAliveDefault("Google"))
    }

    @Test
    fun motionArtworkOnTheLockScreenIsOnByDefault() {
        assertTrue(BackgroundSettings().lockScreenMotionArtwork)
    }
}
