package app.cadenza.remote

import android.content.ComponentName
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.expressiveLightColorScheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelStore
import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.energy.EnergyInputs
import app.cadenza.remote.energy.ThermalLevel
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.ui.DebugScreen
import app.cadenza.remote.ui.settings.EnergyCard
import kotlinx.coroutines.Dispatchers
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/** Renders the Energy settings and Debug readout with synthetic device readings, without a Host or device. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31], qualifiers = "w1000dp-h1100dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class EnergySettingsUiTest {
    @get:Rule(order = 0)
    val testHost =
        object : ExternalResource() {
            override fun before() {
                val context = ApplicationProvider.getApplicationContext<CadenzaApplication>()
                shadowOf(context.packageManager).addActivityIfNotPresent(ComponentName(context, ComponentActivity::class.java))
            }
        }

    @get:Rule(order = 1)
    val compose = createAndroidComposeRule<ComponentActivity>()
    private val app get() = ApplicationProvider.getApplicationContext<CadenzaApplication>()
    private val models = ViewModelStore()
    private lateinit var model: RemoteModel

    @Before
    fun resetStorage() {
        app.database.close()
        app.deleteDatabase("cadence.sqlite")
        compose.runOnUiThread {
            model = RemoteModel(app, ioDispatcher = Dispatchers.Unconfined)
            models.put("remote", model)
        }
        compose.waitUntil(5_000) { model.state.value.loaded }
    }

    @After
    fun closeModel() {
        compose.runOnUiThread { models.clear() }
        app.database.close()
    }

    @Test
    fun choosingAModeUpdatesTheLiveStatusAndIsSaved() {
        showCard()
        compose.onNodeWithText("Plenty of power").assertIsDisplayed()
        compose.onNodeWithText("Always saver").performClick()
        compose.onNodeWithText("Saver is always on").assertIsDisplayed()
        assertEquals("SAVER", app.settings.getString("energy_mode"))
        capture("energy-settings-saver-tablet")
    }

    @Test
    fun theAutomaticOptionsAppearOnlyWhileTheModeIsAutomatic() {
        showCard()
        compose.onNodeWithText("Follow battery saver").assertIsDisplayed()
        compose.onNodeWithText("Always full").performClick()
        compose.onAllNodesWithText("Follow battery saver").assertCountEquals(0)
        compose.onNodeWithText("Animated artwork").assertIsDisplayed()
    }

    @Test
    fun theStatusFollowsDeviceChangesWhileTheCardIsOpen() {
        showCard()
        compose.runOnUiThread { model.energy.onInputs(EnergyInputs(powerSave = true, batteryPercent = 64)) }
        compose.onNodeWithText("Battery saver is on").assertIsDisplayed()
        compose.runOnUiThread { model.energy.onInputs(EnergyInputs(batteryPercent = 64)) }
        compose.onNodeWithText("Plenty of power").assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w360dp-h1500dp-night-mdpi")
    fun phoneDarkLargeTextKeepsEveryControlReachable() {
        showCard(fontScale = 1.6f, dark = true)
        compose.runOnUiThread { model.energy.onInputs(EnergyInputs(batteryPercent = 18, thermal = ThermalLevel.NORMAL)) }
        compose.onNodeWithText("Battery is at 18%").assertIsDisplayed()
        compose.onNodeWithText("Lyric blur").assertIsDisplayed()
        capture("energy-settings-saver-phone-dark-large-text")
    }

    @Test
    @Config(qualifiers = "w360dp-h1100dp-mdpi")
    fun phoneLightShowsTheWarmDeviceReason() {
        showCard()
        compose.runOnUiThread { model.energy.onInputs(EnergyInputs(batteryPercent = 80, thermal = ThermalLevel.WARM)) }
        compose.onNodeWithText("The device is getting warm").assertIsDisplayed()
        capture("energy-settings-balanced-phone-light")
    }

    @OptIn(ExperimentalMaterial3ExpressiveApi::class)
    @Test
    fun debugShowsTheTierReadingsAndKnobs() {
        val energy = model.energyState.value.copy(inputs = EnergyInputs(batteryPercent = 42, powerSave = true))
        compose.setContent {
            MaterialExpressiveTheme {
                DebugScreen(RemoteState(), onBack = {}, energy = energy)
            }
        }
        compose.onNodeWithText("Energy").assertIsDisplayed()
        compose.onNodeWithText("Lyric frame cap").assertIsDisplayed()
    }

    @OptIn(ExperimentalMaterial3ExpressiveApi::class)
    private fun showCard(
        fontScale: Float = 1f,
        dark: Boolean = false,
    ) {
        compose.setContent {
            MaterialExpressiveTheme(colorScheme = if (dark) darkColorScheme() else expressiveLightColorScheme()) {
                CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, fontScale)) {
                    Surface(Modifier.fillMaxSize()) {
                        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp)) { EnergyCard(model) }
                    }
                }
            }
        }
        compose.waitForIdle()
    }

    private fun capture(name: String) {
        compose.waitForIdle()
        val directory = File(requireNotNull(System.getProperty("cadenza.evidence.directory"))).apply { mkdirs() }
        File(directory, "$name.png").outputStream().use {
            check(
                compose
                    .onRoot()
                    .captureToImage()
                    .asAndroidBitmap()
                    .compress(Bitmap.CompressFormat.PNG, 100, it),
            )
        }
    }
}
