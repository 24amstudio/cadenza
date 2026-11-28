package app.cadenza.remote

import android.content.ComponentName
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.expressiveLightColorScheme
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.ui.CastingStatusBar
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/** Renders the casting status line with synthetic data. It does not prove target-device behaviour. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31], qualifiers = "w360dp-h800dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CastingStatusBarRenderTest {
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

    @Test
    fun theStatusLineNamesEveryTargetThatIsReceiving() {
        compose.setContent {
            MaterialExpressiveTheme(colorScheme = expressiveLightColorScheme()) {
                CastingStatusBar(listOf("Living Room iPad", "Bedroom TV"))
            }
        }
        compose.waitForIdle()

        compose.onNodeWithText("Casting to Living Room iPad, Bedroom TV").assertIsDisplayed()
        capture("casting-status-bar")
    }

    private fun capture(name: String) {
        val directory = File(requireNotNull(System.getProperty("cadenza.evidence.directory"))).apply { mkdirs() }
        File(directory, "$name.png").outputStream().use {
            val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
        }
    }
}
