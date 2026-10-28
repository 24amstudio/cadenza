package app.cadenza.remote

import android.content.ComponentName
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.expressiveLightColorScheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.unit.Density
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.data.HostProfile
import app.cadenza.remote.data.LyricDocument
import app.cadenza.remote.data.LyricLine
import app.cadenza.remote.data.Song
import app.cadenza.remote.ui.CadenzaApp
import app.cadenza.remote.ui.ConnectionStatus
import app.cadenza.remote.ui.DebugScreen
import app.cadenza.remote.ui.LyricsScreen
import app.cadenza.remote.ui.StartupScreen
import app.cadenza.remote.ui.position
import app.cadenza.remote.ui.startupBuildLabel
import kotlinx.coroutines.Dispatchers
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
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
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Renders production Compose screens with synthetic local data, without a Host or device. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31], qualifiers = "w1000dp-h800dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class RemoteUiTest {
    @get:Rule(order = 0)
    val testHost =
        object : ExternalResource() {
            override fun before() {
                val context = ApplicationProvider.getApplicationContext<CadenzaApplication>()
                // AGP's release resource APK omits dependency test activities. Register only this rendering host.
                shadowOf(context.packageManager).addActivityIfNotPresent(ComponentName(context, ComponentActivity::class.java))
            }
        }

    @get:Rule(order = 1)
    val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var model: RemoteModel
    private val models = ViewModelStore()
    private val app get() = ApplicationProvider.getApplicationContext<CadenzaApplication>()
    private val hostId = UUID(0, 1).toString()
    private val remoteId = UUID(0, 2).toString()

    @Test
    fun reconnectingStatusUsesAccessibleWifiOffIcon() {
        compose.setContent {
            MaterialExpressiveTheme {
                ConnectionStatus(
                    RemoteState(
                        connecting = true,
                        profile = HostProfile(hostId, "Test Cadenza Host", "10.0.0.5", 43127, "fingerprint", remoteId),
                    ),
                )
            }
        }
        compose.onNodeWithContentDescription("Reconnecting to Test Cadenza Host").assertIsDisplayed()
        compose.onNodeWithText("Connecting to Test Cadenza Host").assertDoesNotExist()
        capture("connection-reconnecting")
    }

    @OptIn(ExperimentalMaterial3ExpressiveApi::class)
    @Test
    fun debugScreenShowsUsageAndCopiesRecentErrors() {
        compose.setContent {
            MaterialExpressiveTheme {
                DebugScreen(
                    RemoteState(
                        debugLog =
                            listOf(
                                DebugLogEntry(System.currentTimeMillis(), "Connection failed", "Host did not respond."),
                            ),
                    ),
                    onBack = {},
                )
            }
        }
        compose.onNodeWithText("Device usage").assertIsDisplayed()
        compose.onNodeWithText("Errors in the last hour").assertIsDisplayed()
        compose.onNodeWithText("Connection failed").assertIsDisplayed()
        compose.onNodeWithText("Copy").performClick()
        compose.onNodeWithText("Copied").assertIsDisplayed()
        capture("debug-tablet")
    }

    @Before
    fun resetSyntheticStorage() {
        app.database.close()
        app.deleteDatabase("cadence.sqlite")
    }

    @After
    fun closeModel() {
        compose.runOnUiThread { models.clear() }
        app.database.close()
    }

    @Test
    fun tabletStartupDisplaysBuildIdentityAtTheBottomCenter() {
        showStartup("startup-tablet")
    }

    @Test
    @Config(qualifiers = "w320dp-h800dp-night-mdpi")
    fun narrowDarkStartupKeepsTheFullBuildLabelAtLargeText() {
        showStartup("startup-phone-dark", fontScale = 2f, dark = true)
    }

    @OptIn(ExperimentalMaterial3ExpressiveApi::class)
    private fun showStartup(
        evidence: String,
        fontScale: Float = 1f,
        dark: Boolean = false,
    ) {
        compose.setContent {
            MaterialExpressiveTheme(colorScheme = if (dark) darkColorScheme() else expressiveLightColorScheme()) {
                CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, fontScale)) {
                    StartupScreen()
                }
            }
        }
        assertTrue(startupBuildLabel.matches(Regex("Cadenza 0\\.0\\.2-(dev|ci|prod)-(source-)?[0-9a-f]{12}-[0-9]{8}\\.[0-9]{6}")))
        val label =
            compose
                .onNodeWithText(startupBuildLabel)
                .assertIsDisplayed()
                .fetchSemanticsNode()
                .boundsInRoot
        val screen = compose.onRoot().fetchSemanticsNode().boundsInRoot
        assertEquals(screen.center.x, label.center.x, 1f)
        assertTrue("Build information must stay near the bottom", label.top > screen.height * 0.8f)
        assertTrue(
            "The complete build label must fit on screen",
            label.left >= screen.left && label.right <= screen.right && label.bottom <= screen.bottom,
        )
        capture(evidence)
    }

    @Test
    fun pairingUsesQrOnly() {
        openApp()
        capture("pairing-tablet")
        compose.onNodeWithText("Scan pairing QR", substring = false).assertIsDisplayed()
        compose.onAllNodesWithText("Pairing details").assertCountEquals(0)
        compose.onAllNodesWithText("Paste pairing details").assertCountEquals(0)
        compose.onAllNodesWithText("Pair", substring = false).assertCountEquals(0)
    }

    @Test
    fun cachedQueueShowsAttributionAndWaitsWithMutationsDisabled() {
        seedProfile()
        openApp(keyboard = true)
        compose.onNodeWithText("Queue").performClick()
        compose.onNodeWithText("Requested by you").assertIsDisplayed()
        compose.onNodeWithText("Requested by Living room").assertIsDisplayed()
        compose.onNodeWithText("Wait ≈ 2:30").assertIsDisplayed()
        compose.onNodeWithText("Wait ≈ 6:00").assertIsDisplayed()
        compose.onNodeWithText("Total remaining ≈ 7:30").assertIsDisplayed()
        compose.onAllNodesWithText("Remove").assertCountEquals(2)
        compose.onAllNodesWithText("Remove")[0].assertIsNotEnabled()
        compose.onAllNodesWithText("Remove")[1].assertIsNotEnabled()
        capture("queue-tablet")
        val queueBefore =
            model.state.value.snapshot
                ?.queue
                ?.map { it.id }
        compose.onAllNodesWithText("Sing along").assertCountEquals(0)
        navigate("Playing")
        compose.onRoot().performKeyInput { pressKey(Key.Tab) }
        compose.onNodeWithText("Lyrics").performSemanticsAction(SemanticsActions.RequestFocus)
        compose
            .onNodeWithText("Lyrics")
            .assertIsFocused()
            .assertIsNotSelected()
            .performClick()
        compose.onNodeWithText("Lyrics").assertIsSelected()
        compose.onNodeWithText("Synchronization paused.").assertIsDisplayed()
        compose.onNodeWithContentDescription("Reconnecting to Host").assertIsDisplayed()
        compose.onNodeWithText("Retry lyrics").assertIsNotEnabled()
        compose.onNodeWithText("Requested by Living room").assertIsDisplayed()
        compose.onNodeWithContentDescription("Playback position").assertIsNotEnabled()
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.onNodeWithText("Lyrics").assertIsNotSelected().assertIsFocused()
        assertEquals(
            queueBefore,
            model.state.value.snapshot
                ?.queue
                ?.map { it.id },
        )
    }

    @Test
    @Config(qualifiers = "w360dp-h800dp-mdpi")
    fun compactLyricsModeKeepsTransportVisibleAndReturnsToPlayer() {
        seedProfile()
        openApp()
        compose.onNodeWithText("Lyrics").performClick()
        compose.onNodeWithText("Lyrics").assertIsSelected()
        compose.onNodeWithContentDescription("Back to player").assertIsDisplayed()
        compose.onNodeWithContentDescription("Playback position").assertIsDisplayed()
        compose.onNodeWithContentDescription("Resume in Cadenza Host").assertIsDisplayed()
        compose.onAllNodesWithContentDescription("Queue").assertCountEquals(0)
        capture("integrated-lyrics-phone")
        compose.onNodeWithText("Lyrics").performClick()
        compose.onNodeWithText("Lyrics").assertIsNotSelected()
    }

    @Test
    @Config(qualifiers = "w360dp-h800dp-mdpi")
    fun lyricsModeSurvivesStateRestoration() {
        seedProfile()
        createModel()
        val restoration = StateRestorationTester(compose)
        restoration.setContent { CadenzaApp(model, installUpdate = {}) }
        compose.waitUntil(5_000) { model.state.value.loaded }
        compose.onNodeWithText("Lyrics").performClick()
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithText("Lyrics").assertIsSelected()
        compose.onNodeWithContentDescription("Back to player").performClick()
        compose.onNodeWithText("Lyrics").assertIsNotSelected()
    }

    @Test
    @Config(qualifiers = "w320dp-h960dp-mdpi")
    fun largeTextLyricsKeepsExitAndTransportVisible() {
        seedProfile()
        openApp(fontScale = 2f)
        compose.onNodeWithText("Lyrics").performClick()
        compose.onNodeWithContentDescription("Back to player").assertIsDisplayed()
        compose.onNodeWithText("Requested by Living room").assertIsDisplayed()
        compose.onNodeWithContentDescription("Playback position").assertIsDisplayed()
        compose.onNodeWithContentDescription("Resume in Cadenza Host").assertIsDisplayed()
        capture("integrated-lyrics-large-text")
    }

    @Test
    @Config(qualifiers = "w1000dp-h800dp-night-mdpi")
    fun lyricsModeUsesDarkSystemTheme() {
        seedProfile()
        openApp()
        compose.onNodeWithText("Lyrics").performClick()
        compose.onNodeWithText("Synchronization paused.").assertIsDisplayed()
        capture("integrated-lyrics-tablet-dark")
    }

    @Test
    fun expandedHomeShowsBothPanesAndLocalFavoritesWorkOffline() {
        seedProfile()
        val song = Song("catalog", "9876", "Offline favorite", "Synthetic artist", "Album", 180_000)
        app.library.setFavorite(song, true)
        openApp()
        compose.onNodeWithText("Library").assertIsDisplayed()
        compose.onAllNodesWithText("Now playing").assertCountEquals(2)
        compose.onNodeWithText("Favorites · 1").performClick()
        compose.onNodeWithText("Offline favorite").performClick()
        compose.onNodeWithText("Add to queue").assertIsNotEnabled()
        compose.onNodeWithText("Play next").assertIsNotEnabled()
        compose.onNodeWithText("Play now").assertIsNotEnabled()
        capture("favorites-tablet")
        compose.onNodeWithContentDescription("Remove from Favorites").performClick()
        compose.waitUntil(5_000) {
            compose.onAllNodesWithText("This song is no longer in the queue or Favorites.").fetchSemanticsNodes().size == 1
        }
        assertTrue(
            model.state.value.favorites
                .isEmpty(),
        )
        assertTrue(
            app.library
                .load()
                .songs
                .isEmpty(),
        )
    }

    @Test
    @Config(qualifiers = "w360dp-h800dp-mdpi")
    fun compactHomeKeepsFavoriteSelectionAfterNavigatingAway() {
        seedProfile()
        app.library.setFavorite(Song("catalog", "9876", "Offline favorite", "Synthetic artist"), true)
        openApp()
        compose.onNodeWithText("Queue and Favorites").performClick()
        compose.onNodeWithText("Favorites · 1").performClick()
        compose.onNodeWithText("Offline favorite").performClick()
        compose.onNodeWithContentDescription("Remove from Favorites").assertIsDisplayed()
        navigate("Settings")
        navigate("Playing")
        compose.onNodeWithContentDescription("Remove from Favorites").assertIsDisplayed()
        capture("favorites-phone")
    }

    @Test
    fun nameAndThemePreferencesPersistAndUseVisibleFeedback() {
        seedProfile()
        openApp()
        navigate("Settings")
        compose.onNodeWithText("Remote name").performTextReplacement("Bedroom tablet")
        compose.onNodeWithText("Dark", substring = false).performClick()
        compose.onNodeWithText("Save preferences").performScrollTo().performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Preferences saved").fetchSemanticsNodes().size == 1 }
        assertEquals("Bedroom tablet", model.state.value.clientName)
        compose.onNodeWithText("Preferences saved").assertIsDisplayed()
        assertEquals("Bedroom tablet", app.settings.getString("client_name", null))
        assertEquals("DARK", app.settings.getString("theme", null))
        compose.onNodeWithText("Changes in this build").performScrollTo().performClick()
        try {
            compose.waitUntil(5_000) { compose.onAllNodesWithText("Changelog").fetchSemanticsNodes().size == 1 }
        } catch (error: androidx.compose.ui.test.ComposeTimeoutException) {
            capture("settings-changelog-timeout")
            throw AssertionError("Changelog outcome: ${model.state.value.changelog}; prompt: ${model.state.value.prompt}", error)
        }
        compose.onNodeWithText("Changelog").assertIsDisplayed()
        capture("changelog", compose.onNode(isDialog()))
        compose.onNodeWithText("Close").performClick()
        compose.onNodeWithText("Compare published changes").performScrollTo().performClick()
        compose.waitUntil(5_000) { model.state.value.changelog != null || model.state.value.prompt != null }
        if (model.state.value.prompt != null) {
            compose.onNodeWithText("Changes could not be compared").assertIsDisplayed()
        } else {
            compose.onNode(isDialog()).assertIsDisplayed()
        }
    }

    @Test
    @Config(qualifiers = "w320dp-h800dp-mdpi")
    fun narrowPhoneCanNavigateAndDisplayEmptyQueue() {
        seedProfile(emptyQueue = true)
        openApp()
        compose.onNodeWithContentDescription("Queue").performClick()
        capture("queue-phone")
        compose.onNodeWithText("Queue is empty").assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w1000dp-h800dp-night-mdpi")
    fun darkPlayingScreenRendersTheSavedRequest() {
        seedProfile()
        openApp()
        compose.onNodeWithText("Requested by Living room").assertIsDisplayed()
        capture("playing-tablet-dark")
    }

    @Test
    fun cachedFormatsAreNotPresentedAsCurrentPlaybackObservations() {
        seedProfile()
        app.database.saveState(
            hostId,
            snapshot(false)
                .put("quality", "lossless")
                .put("mixing", true)
                .put("incoming", song("Cached incoming song", 180_000)),
        )
        openApp()
        compose.onNodeWithText("Quality waiting for Cadenza Host").assertIsDisplayed()
        compose.onNodeWithText("AutoMix status waiting for Cadenza Host").assertIsDisplayed()
        compose.onNodeWithText("Lossless").assertDoesNotExist()
        compose.onNodeWithText("AutoMix â†’ Cached incoming song").assertDoesNotExist()
    }

    @Test
    @Config(qualifiers = "w320dp-h960dp-mdpi")
    fun pairingReflowsWithDoubleSizeText() {
        openApp(fontScale = 2f)
        capture("pairing-phone-large-text")
        compose.onNodeWithText("Pair with Cadenza Host").assertIsDisplayed()
        compose
            .onNodeWithText("Scan pairing QR", substring = false)
            .performScrollTo()
            .assertIsDisplayed()
        capture("pairing-phone-large-text-bottom")
    }

    @Test
    fun searchKeepsEnteredTextAndSourceWhenReturningFromSettings() {
        seedProfile()
        openApp()
        navigate("Search")
        compose.onNodeWithText("Song, artist, or album").performTextInput("A saved search")
        compose.onNodeWithText("Host library").performClick()
        navigate("Settings")
        compose.onNodeWithText("Change this setting in Cadenza Host.").performScrollTo().assertIsDisplayed()
        navigate("Search")
        compose.onNodeWithText("A saved search").assertIsDisplayed()
        compose.onNodeWithText("Host library").assertIsSelected()
        capture("search-tablet")
    }

    @Test
    fun analyticsDisplaysCommittedPersonalCountsAndObservedTime() {
        seedProfile()
        app.database.remember(hostId, listOf(Song("catalog", "123", "Personal favorite", "Synthetic artist")))
        for ((sequence, duration, count) in listOf(Triple(1L, 5_000L, 1), Triple(2L, 3_000L, 0))) {
            app.database.applyCredit(
                hostId,
                JSONObject()
                    .put("sequence", sequence)
                    .put("event_id", UUID(4, sequence).toString())
                    .put("occurrence_id", UUID(5, 1).toString())
                    .put("song", JSONObject().put("source", "catalog").put("id", "123"))
                    .put("played_ms_delta", duration)
                    .put("play_count_delta", count),
            )
        }
        openApp()
        navigate("Analytics")
        // Waiting on rendered semantics also drains main-looper continuations after SQLite IO.
        compose.waitUntil(5_000) { compose.onAllNodesWithText("1 play · 0:08").fetchSemanticsNodes().size == 1 }
        assertEquals(1, model.state.value.statistics.size)
        compose.onNodeWithText("1. Personal favorite").assertIsDisplayed()
        compose.onNodeWithText("1 play · 0:08").assertIsDisplayed()
        capture("analytics-tablet")
    }

    @OptIn(ExperimentalMaterial3ExpressiveApi::class)
    @Test
    fun cachedLyricsShowEnglishWithoutClaimingLiveSynchronization() {
        seedProfile()
        createModel()
        val document =
            LyricDocument(
                UUID(0, 11).toString(),
                UUID(0, 20).toString(),
                "machine",
                listOf(
                    LyricLine("first", "La nuit sâ€™Ã©veille", 0, 25_000, "The night awakens"),
                    LyricLine("second", "Je chante avec toi", 30_000, 35_000, "I sing with you"),
                ),
                null,
            )
        compose.setContent {
            val state by model.state.collectAsStateWithLifecycle()
            MaterialExpressiveTheme { LyricsScreen(model, state.copy(lyrics = document)) }
        }
        compose.waitUntil(5_000) {
            model.state.value.loaded
        }
        compose.onNodeWithText("English machine translation").assertIsDisplayed()
        compose.onNodeWithText("Synchronization paused.").assertIsDisplayed()
        compose.onNodeWithText("I sing with you").assertIsNotSelected()
        compose.onNodeWithText("The night awakens").assertIsNotSelected()
        capture("lyrics-tablet")
    }

    @OptIn(ExperimentalMaterial3ExpressiveApi::class)
    @Test
    fun scrollingLyricsCanResumeFollowing() {
        seedProfile()
        createModel()
        val document =
            LyricDocument(
                UUID(0, 11).toString(),
                UUID(0, 20).toString(),
                "original",
                (1..24).map { LyricLine("line-$it", "Line $it", 0, 0, null) },
                null,
            )
        compose.setContent {
            val state by model.state.collectAsStateWithLifecycle()
            MaterialExpressiveTheme { LyricsScreen(model, state.copy(lyrics = document)) }
        }
        compose.waitUntil(5_000) { model.state.value.loaded }
        compose.onNodeWithText("Lyrics without timing").assertIsDisplayed()
        compose.onNode(hasScrollAction()).performTouchInput { swipeUp() }
        compose.onNodeWithText("Follow current line").assertIsDisplayed().performClick()
        compose.onAllNodesWithText("Follow current line").assertCountEquals(0)
    }

    @Test
    @Config(qualifiers = "w320dp-h960dp-mdpi")
    fun queueTimingRemainsReadableWithDoubleSizeText() {
        seedProfile()
        openApp(fontScale = 2f)
        navigate("Queue")
        compose.onNodeWithText("Wait ≈ 2:30").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Total remaining ≈ 7:30").assertIsDisplayed()
        capture("queue-phone-large-text")
    }

    @Test
    fun playbackTickerSuspendsWhenItsLifecycleStops() {
        createModel()
        val owner = compose.runOnUiThread { PageLifecycle().apply { lifecycle.currentState = Lifecycle.State.STARTED } }
        val updates = AtomicInteger()
        val advancing = mutableStateOf(true)
        val renderedAdvancing = AtomicBoolean(true)
        compose.setContent {
            CompositionLocalProvider(LocalLifecycleOwner provides owner) {
                val elapsed = position(model, 50, advance = advancing.value)
                SideEffect {
                    updates.incrementAndGet()
                    renderedAdvancing.set(advancing.value)
                }
                Text(elapsed.toString())
            }
        }
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(240)
        compose.waitForIdle()
        assertTrue("Playback must update while its screen is started", updates.get() > 1)
        compose.runOnUiThread { owner.lifecycle.currentState = Lifecycle.State.CREATED }
        compose.mainClock.advanceTimeByFrame()
        compose.waitForIdle()
        val paused = updates.get()
        compose.mainClock.advanceTimeBy(240)
        compose.waitForIdle()
        assertEquals("A stopped screen must not keep ticking", paused, updates.get())
        compose.runOnUiThread { owner.lifecycle.currentState = Lifecycle.State.STARTED }
        compose.mainClock.advanceTimeBy(240)
        compose.waitForIdle()
        assertTrue("Playback must resume updates when its screen starts", updates.get() > paused)
        compose.runOnUiThread { advancing.value = false }
        compose.mainClock.advanceTimeUntil(1_000) { !renderedAdvancing.get() }
        compose.waitForIdle()
        val stoppedPlayback = updates.get()
        compose.mainClock.advanceTimeBy(240)
        compose.waitForIdle()
        assertEquals("Paused playback must not keep ticking", stoppedPlayback, updates.get())
    }

    @Test
    fun pinnedSongStatusSurvivesTheActivityBackgroundTransition() {
        createModel()
        compose.waitUntil(5_000) { model.state.value.loaded }
        compose.runOnUiThread {
            model.monitorSong()
            model.setForeground(false)
        }
        assertTrue(model.state.value.sessionActive)
        assertTrue(model.state.value.monitoringSong)
        compose.runOnUiThread { model.endSessionStatus() }
        assertTrue(!model.state.value.sessionActive)
        assertTrue(!model.state.value.monitoringSong)
    }

    private class PageLifecycle : LifecycleOwner {
        override val lifecycle = LifecycleRegistry(this)
    }

    private fun openApp(
        fontScale: Float = 1f,
        keyboard: Boolean = false,
    ) {
        createModel()
        compose.setContent {
            val inputMode = LocalInputModeManager.current
            LaunchedEffect(keyboard) {
                if (keyboard) inputMode.requestInputMode(InputMode.Keyboard)
            }
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, fontScale)) {
                CadenzaApp(model, installUpdate = {})
            }
        }
        compose.waitUntil(5_000) { model.state.value.loaded }
        compose.waitForIdle()
    }

    private fun createModel() {
        compose.runOnUiThread {
            // Control scheduling for native rendering tests; SQLite still executes, and production defaults to IO.
            model = RemoteModel(app, ioDispatcher = Dispatchers.Unconfined)
            models.put("remote", model)
        }
    }

    private fun navigate(label: String) {
        compose.onNode(isSelectable() and hasClickAction() and (hasText(label) or hasContentDescription(label))).performClick()
    }

    private fun seedProfile(emptyQueue: Boolean = false) {
        val profile =
            HostProfile(
                hostId,
                "Test Cadenza Host",
                "10.0.0.5",
                43127,
                TestCertificate.fingerprint,
                remoteId,
                TestCertificate.encoded,
            )
        app.database.saveProfile(profile)
        app.database.saveState(hostId, snapshot(emptyQueue))
        app.settings.write("active_host" to hostId)
    }

    private fun snapshot(emptyQueue: Boolean): JSONObject {
        val queue = JSONArray()
        if (!emptyQueue) {
            queue.put(entry(4, remoteId, "Android Remote", "A long requested song title with several words", 210_000, 150_000))
            queue.put(entry(5, UUID(0, 3).toString(), "Living room", "Second request", 90_000, 360_000))
        }
        return JSONObject()
            .put("host_id", hostId)
            .put("host_epoch", UUID(0, 10).toString())
            .put("revision", 1)
            .put("sequence", 1)
            .put("host_time_ms", 1_000)
            .put("allow_cross_remote_edits", false)
            .put("playing", false)
            .put("volume", 40)
            .put("quality", "unknown")
            .put(
                "current",
                JSONObject()
                    .put("occurrence_id", UUID(0, 11).toString())
                    .put("entry_id", UUID(0, 12).toString())
                    .put("requested_by", UUID(0, 3).toString())
                    .put("requester_name", "Living room")
                    .put("song", song("Current song", 180_000))
                    .put("position_ms", 30_000)
                    .put("sampled_at_host_ms", 1_000),
            ).put("queue", queue)
            .put("total_remaining_ms", if (emptyQueue) 150_000 else 450_000)
            .put("synchronized", true)
            .put("observation_gap", false)
    }

    private fun entry(
        id: Long,
        owner: String,
        name: String,
        title: String,
        duration: Long,
        wait: Long,
    ): JSONObject =
        JSONObject()
            .put("id", UUID(0, id).toString())
            .put("requested_by", owner)
            .put("requester_name", name)
            .put("song", song(title, duration))
            .put("estimated_wait_ms", wait)

    private fun song(
        title: String,
        duration: Long,
    ): JSONObject =
        JSONObject()
            .put(
                "source",
                "catalog",
            ).put("id", "123")
            .put("title", title)
            .put("artist", "Synthetic artist")
            .put("duration_ms", duration)

    private fun capture(
        name: String,
        node: SemanticsNodeInteraction = compose.onRoot(),
    ) {
        compose.waitForIdle()
        val directory = File(requireNotNull(System.getProperty("cadenza.evidence.directory"))).apply { mkdirs() }
        File(directory, "$name.png").outputStream().use {
            check(node.captureToImage().asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, it))
        }
    }
}
