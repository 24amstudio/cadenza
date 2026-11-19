package app.cadenza.remote.energy

import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.CadenzaApplication
import app.cadenza.remote.data.CadenzaDatabase
import app.cadenza.remote.data.StoredSettings
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31])
class EnergySettingsStoreTest {
    private val app get() = ApplicationProvider.getApplicationContext<CadenzaApplication>()
    private lateinit var database: CadenzaDatabase

    @Before
    fun open() {
        app.database.close()
        app.deleteDatabase("cadence.sqlite")
        database = CadenzaDatabase(app)
    }

    @After
    fun close() {
        database.close()
    }

    @Test
    fun anInstallWithoutStoredEnergySettingsGetsTheDefaults() {
        assertEquals(EnergySettings(), EnergySettingsStore.load(StoredSettings(database, "app")))
    }

    @Test
    fun savedChoicesSurviveReopeningTheDatabase() {
        val chosen =
            EnergySettings(
                mode = EnergyMode.SAVER,
                followSystemSaver = false,
                lowBatteryPercent = 10,
                reduceWhenHot = false,
                fullWhileCharging = false,
                motionArtworkInSaver = true,
                lyricBlurInSaver = true,
            )
        EnergySettingsStore.save(StoredSettings(database, "app"), chosen)
        database.close()
        database = CadenzaDatabase(app)
        assertEquals(chosen, EnergySettingsStore.load(StoredSettings(database, "app")))
    }

    @Test
    fun unreadableValuesFallBackToTheDefaultInsteadOfFailing() {
        val store = StoredSettings(database, "app")
        store.write("energy_mode" to "TURBO", "energy_low_battery" to "17", "energy_follow_system" to "maybe")
        assertEquals(EnergySettings(), EnergySettingsStore.load(store))
    }
}
