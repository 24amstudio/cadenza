package app.cadenza.remote

import android.content.ComponentName
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.expressiveLightColorScheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.data.AudioOutput
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.ui.OutputChooser
import kotlinx.coroutines.Dispatchers
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/** Renders the output button with synthetic data. It does not prove target-device behaviour. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31], qualifiers = "w360dp-h800dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class OutputChooserRenderTest {
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

    private val outputs = listOf(AudioOutput("speakers", "MacBook Air Speakers", "built-in", true))

    private fun render(remoteAudioTarget: String?) {
        val app = ApplicationProvider.getApplicationContext<CadenzaApplication>()
        val model = RemoteModel(app, ioDispatcher = Dispatchers.Unconfined)
        compose.setContent {
            MaterialExpressiveTheme(colorScheme = expressiveLightColorScheme()) {
                Surface(Modifier.fillMaxSize()) {
                    Column(Modifier.padding(16.dp)) {
                        OutputChooser(model, outputs, cast = null, remoteAudioTarget = remoteAudioTarget, enabled = true)
                    }
                }
            }
        }
        compose.waitForIdle()
    }

    private fun capture(name: String) {
        val directory = File(requireNotNull(System.getProperty("cadenza.evidence.directory"))).apply { mkdirs() }
        File(directory, "$name.png").outputStream().use {
            val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
        }
    }

    @Test
    fun anIdleOutputButtonShowsTheDefaultOutput() {
        render(remoteAudioTarget = null)

        compose.onNodeWithContentDescription("Output: MacBook Air Speakers").assertIsDisplayed()
        capture("output-chooser-idle")
    }

    @Test
    fun aRemoteStreamNamesTheRemoteOnTheOutputButton() {
        render(remoteAudioTarget = "Living Room iPad")

        compose.onNodeWithContentDescription("Output: Remote: Living Room iPad").assertIsDisplayed()
        capture("output-chooser-casting")
    }
}
