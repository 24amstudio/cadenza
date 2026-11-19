package app.cadenza.remote.energy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class EnergyAssessorTest {
    @Test
    fun aBatterySaverToggleChangesTheProfileAtOnce() {
        val assessor = EnergyAssessor()
        assessor.onInputs(EnergyInputs(batteryPercent = 70))
        assertEquals(EnergyTier.FULL, assessor.profile.value.tier)
        assessor.onInputs(EnergyInputs(batteryPercent = 70, powerSave = true))
        assertEquals(EnergyTier.SAVER, assessor.profile.value.tier)
        assertEquals("Battery saver is on", assessor.state.value.assessment.message)
        assessor.onInputs(EnergyInputs(batteryPercent = 70, powerSave = false))
        assertEquals(EnergyTier.FULL, assessor.profile.value.tier)
    }

    @Test
    fun aBatteryPercentChangeInsideATierKeepsTheSameProfile() {
        val assessor = EnergyAssessor()
        assessor.onInputs(EnergyInputs(batteryPercent = 70))
        val before = assessor.profile.value
        assessor.onInputs(EnergyInputs(batteryPercent = 69))
        assertSame(before, assessor.profile.value)
        assertEquals(69, assessor.state.value.inputs.batteryPercent)
    }

    @Test
    fun changedSettingsApplyAtOnceAndPersistOnce() {
        val saved = mutableListOf<EnergySettings>()
        val assessor = EnergyAssessor(persist = { saved += it })
        assessor.onInputs(EnergyInputs(batteryPercent = 70))
        assessor.updateSettings { it.copy(mode = EnergyMode.SAVER) }
        assessor.updateSettings { it.copy(mode = EnergyMode.SAVER) }
        assertEquals(EnergyTier.SAVER, assessor.profile.value.tier)
        assertEquals(listOf(EnergyMode.SAVER), saved.map { it.mode })
    }

    @Test
    fun restoringStoredSettingsDoesNotWriteThemBack() {
        val saved = mutableListOf<EnergySettings>()
        val assessor = EnergyAssessor(persist = { saved += it })
        assessor.restore(EnergySettings(mode = EnergyMode.FULL))
        assertEquals(EnergyMode.FULL, assessor.state.value.settings.mode)
        assertEquals(emptyList<EnergySettings>(), saved)
    }
}
