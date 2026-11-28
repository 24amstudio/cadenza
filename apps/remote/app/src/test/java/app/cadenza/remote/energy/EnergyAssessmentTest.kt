package app.cadenza.remote.energy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EnergyAssessmentTest {
    private val settings = EnergySettings()
    private val healthy = EnergyInputs(batteryPercent = 80)

    private fun tier(
        inputs: EnergyInputs,
        config: EnergySettings = settings,
    ) = assessEnergy(inputs, config).tier

    @Test
    fun aHealthyDeviceRunsFull() {
        val result = assessEnergy(healthy, settings)
        assertEquals(EnergyTier.FULL, result.tier)
        assertEquals(EnergyReason.NORMAL, result.reason)
    }

    @Test
    fun systemBatterySaverForcesSaverEvenWhileCharging() {
        val result = assessEnergy(healthy.copy(powerSave = true, charging = true), settings)
        assertEquals(EnergyTier.SAVER, result.tier)
        assertEquals("Battery saver is on", result.message)
    }

    @Test
    fun theUserCanStopFollowingTheSystemSaver() {
        assertEquals(EnergyTier.FULL, tier(healthy.copy(powerSave = true), settings.copy(followSystemSaver = false)))
    }

    @Test
    fun lowBatteryUsesSaverAtTheThresholdAndBalancedJustAbove() {
        assertEquals(EnergyTier.SAVER, tier(healthy.copy(batteryPercent = 20)))
        assertEquals("Battery is at 20%", assessEnergy(healthy.copy(batteryPercent = 20), settings).message)
        assertEquals(EnergyTier.BALANCED, tier(healthy.copy(batteryPercent = 30)))
        assertEquals(EnergyTier.FULL, tier(healthy.copy(batteryPercent = 31)))
    }

    @Test
    fun aThresholdOfOffIgnoresTheBatteryLevel() {
        assertEquals(EnergyTier.FULL, tier(healthy.copy(batteryPercent = 3), settings.copy(lowBatteryPercent = 0)))
    }

    @Test
    fun chargingKeepsFullAtLowBatteryButOnlyWhenAllowed() {
        val low = healthy.copy(batteryPercent = 5, charging = true)
        assertEquals(EnergyTier.FULL, tier(low))
        assertEquals(EnergyTier.SAVER, tier(low, settings.copy(fullWhileCharging = false)))
    }

    @Test
    fun heatOutranksCharging() {
        assertEquals(EnergyTier.SAVER, tier(healthy.copy(charging = true, thermal = ThermalLevel.HOT)))
        assertEquals(EnergyTier.BALANCED, tier(healthy.copy(charging = true, thermal = ThermalLevel.WARM)))
    }

    @Test
    fun heatIsIgnoredWhenTheUserTurnedItOff() {
        assertEquals(EnergyTier.FULL, tier(healthy.copy(thermal = ThermalLevel.HOT), settings.copy(reduceWhenHot = false)))
    }

    @Test
    fun aDarkScreenIsBalanced() {
        assertEquals(EnergyTier.BALANCED, tier(healthy.copy(interactive = false)))
    }

    @Test
    fun manualModesIgnoreTheDevice() {
        val worst = EnergyInputs(powerSave = true, batteryPercent = 1, thermal = ThermalLevel.HOT)
        assertEquals(EnergyTier.FULL, tier(worst, settings.copy(mode = EnergyMode.FULL)))
        assertEquals(EnergyTier.SAVER, tier(healthy.copy(charging = true), settings.copy(mode = EnergyMode.SAVER)))
    }

    @Test
    fun saverTurnsOffBlurAndMotionUnlessAllowed() {
        val saver = EnergyProfile.of(EnergyTier.SAVER, settings)
        assertFalse(saver.lyricBlur)
        assertFalse(saver.motionArtwork)
        val allowed = EnergyProfile.of(EnergyTier.SAVER, settings.copy(lyricBlurInSaver = true, motionArtworkInSaver = true))
        assertTrue(allowed.lyricBlur)
        assertTrue(allowed.motionArtwork)
    }

    @Test
    fun lowerTiersNeverDoMoreWorkThanHigherOnes() {
        val full = EnergyProfile.of(EnergyTier.FULL, settings)
        val balanced = EnergyProfile.of(EnergyTier.BALANCED, settings)
        val saver = EnergyProfile.of(EnergyTier.SAVER, settings)
        assertTrue(full.lyricFrameCapFps > balanced.lyricFrameCapFps && balanced.lyricFrameCapFps > saver.lyricFrameCapFps)
        assertTrue(full.lyricTickMs < balanced.lyricTickMs && balanced.lyricTickMs < saver.lyricTickMs)
        assertTrue(full.artworkMaxEdgePx > balanced.artworkMaxEdgePx && balanced.artworkMaxEdgePx > saver.artworkMaxEdgePx)
        assertTrue(full.statusIntervalMs < saver.statusIntervalMs)
    }

    @Test
    fun saverPrefersEfficientTransportOnlyWhenTheUserLeftTheDefault() {
        val saver = EnergyProfile.of(EnergyTier.SAVER, settings)
        assertEquals("remote_efficiency", saver.reportedPreference("balanced"))
        assertEquals("latency", saver.reportedPreference("latency"))
        assertEquals("balanced", EnergyProfile.Full.reportedPreference("balanced"))
    }
}
