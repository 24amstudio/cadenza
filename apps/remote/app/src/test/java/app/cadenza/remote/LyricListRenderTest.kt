package app.cadenza.remote

import android.content.ComponentName
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.expressiveLightColorScheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.data.LyricDocument
import app.cadenza.remote.data.LyricLine
import app.cadenza.remote.data.LyricWord
import app.cadenza.remote.data.LyricsTextSize
import app.cadenza.remote.ui.lyrics.FollowActiveLine
import app.cadenza.remote.ui.lyrics.LyricList
import app.cadenza.remote.ui.lyrics.LyricPlayback
import app.cadenza.remote.ui.lyrics.LyricsClock
import app.cadenza.remote.ui.lyrics.activeLineIndices
import app.cadenza.remote.ui.lyrics.rememberUserScrollConnection
import app.cadenza.remote.ui.lyrics.sweepTargets
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/** Renders the lyric list with a duet that overlaps in time. Synthetic data; it does not prove target-device behaviour. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31], qualifiers = "w360dp-h800dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LyricListRenderTest {
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

    // The second singer's lines (odd) sit on the end edge. Line 7 is a background vocal inside line 6.
    private val document =
        LyricDocument(
            "00000000-0000-4000-8000-000000000001",
            "00000000-0000-4000-8000-000000000002",
            "none",
            (0..11).map { index ->
                val (start, end) = if (index == 7) 25_000L to 27_500L else index * 4_000L to index * 4_000L + 4_000L
                val words = listOf("Lyric ", "line ", "number ", "$index")
                val step = (end - start) / words.size
                LyricLine(
                    "l$index",
                    words.joinToString(""),
                    start,
                    end,
                    if (index % 3 == 2) "Translation of line $index" else null,
                    words.mapIndexed { i, text -> LyricWord(text, start + i * step, start + (i + 1) * step) },
                    align = if (index % 2 == 1) "end" else "start",
                )
            },
            null,
        )

    private fun render(
        positionMs: Long,
        fontScale: Float = 1f,
    ) {
        compose.setContent {
            val scheme = if (isSystemInDarkTheme()) darkColorScheme() else expressiveLightColorScheme()
            MaterialExpressiveTheme(colorScheme = scheme) {
                CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, fontScale)) {
                    Surface(Modifier.fillMaxSize()) {
                        Box(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 12.dp)) {
                            val list = rememberLazyListState()
                            val active = activeLineIndices(document.lines, positionMs)
                            FollowActiveLine(list, active.min(), document.revision, following = true, reduced = false)
                            LyricList(
                                document = document,
                                playback =
                                    LyricPlayback(
                                        positionMs,
                                        active,
                                        sweepTargets(document.lines, positionMs),
                                        synced = true,
                                        clock = remember { LyricsClock { positionMs } },
                                    ),
                                list = list,
                                userScroll = rememberUserScrollConnection {},
                                reduced = false,
                                translationRevealed = true,
                                textSize = LyricsTextSize.STANDARD,
                                canSeek = { true },
                                onSeek = {},
                            )
                        }
                    }
                }
            }
        }
        compose.waitForIdle()
    }

    private fun shown(text: String): Boolean = runCatching { compose.onNodeWithText(text).assertIsDisplayed() }.isSuccess

    private fun capture(name: String) {
        val directory = File(requireNotNull(System.getProperty("cadenza.evidence.directory"))).apply { mkdirs() }
        File(directory, "$name.png").outputStream().use {
            val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
        }
    }

    @Test
    fun theActiveLineOpensWithTwoPreviousLinesAboveItWithoutScrolling() {
        // Lines 6 and 7 sound together. The list is in place on first composition, with lines 4 and 5 above line 6.
        render(26_000)
        assertTrue(shown("Lyric line number 6"))
        assertTrue(shown("Lyric line number 7"))
        assertTrue(shown("Lyric line number 5"))
        assertTrue(shown("Lyric line number 4"))
        assertTrue("A third previous line must be out of view", !shown("Lyric line number 3"))
        capture("lyrics-list-phone-light")
    }

    @Test
    @Config(qualifiers = "w360dp-h800dp-night-mdpi")
    fun darkPhoneListKeepsInactiveLinesLegible() {
        render(26_000)
        assertTrue(shown("Lyric line number 6"))
        capture("lyrics-list-phone-dark")
    }

    @Test
    @Config(qualifiers = "w1000dp-h800dp-night-mdpi")
    fun tabletListWithOpeningLinesRestsLineZeroAtTheTop() {
        render(1_000)
        assertTrue(shown("Lyric line number 0"))
        assertTrue(shown("Lyric line number 1"))
        capture("lyrics-list-tablet-dark-opening")
    }

    @Test
    @Config(qualifiers = "w320dp-h960dp-mdpi")
    fun largeTextListStillShowsTheActiveLine() {
        render(26_000, fontScale = 2f)
        assertTrue(shown("Lyric line number 6"))
        capture("lyrics-list-phone-large-text")
    }
}
