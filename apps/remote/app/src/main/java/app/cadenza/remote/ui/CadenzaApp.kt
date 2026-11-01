package app.cadenza.remote.ui

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.expressiveLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.cadenza.remote.data.ThemePreference
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.dismissNotice
import app.cadenza.remote.model.dismissPrompt
import app.cadenza.remote.model.id
import app.cadenza.remote.model.recordUserAction
import app.cadenza.remote.model.requestArtwork

private data class Destination(
    val id: Int,
    val label: String,
    val icon: CadenzaIcon,
)

private val destinations =
    listOf(
        Destination(0, "Home", CadenzaIcon.HOME),
        Destination(1, "Search", CadenzaIcon.SEARCH),
        Destination(2, "Queue", CadenzaIcon.QUEUE),
        Destination(4, "Analytics", CadenzaIcon.ANALYTICS),
        Destination(5, "Settings", CadenzaIcon.SETTINGS),
    )

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun CadenzaApp(
    model: RemoteModel,
    installUpdate: (String) -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    var destination by rememberSaveable { mutableIntStateOf(0) }
    var lyricsMode by rememberSaveable { mutableStateOf(false) }
    var restoreLyricsFocus by remember { mutableStateOf(false) }
    var nowPlayingOpen by rememberSaveable { mutableStateOf(false) }
    val screenState = rememberSaveableStateHolder()

    fun closeLyrics() {
        lyricsMode = false
        restoreLyricsFocus = true
    }
    val darkTheme =
        state.theme == ThemePreference.DARK ||
            (state.theme == ThemePreference.SYSTEM && isSystemInDarkTheme())
    MaterialExpressiveTheme(
        colorScheme =
            if (darkTheme) {
                darkColorScheme()
            } else {
                expressiveLightColorScheme()
            },
    ) {
        val view = LocalView.current
        SideEffect {
            val window = (view.context as? Activity)?.window ?: return@SideEffect
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !darkTheme
                isAppearanceLightNavigationBars = !darkTheme
            }
        }
        if (!state.loaded) {
            StartupScreen()
            return@MaterialExpressiveTheme
        }
        CompositionLocalProvider(LocalArtworkHost provides ArtworkHost(state.artwork) { url -> model.requestArtwork(url) }) {
            LaunchedEffect(state.notice?.id) {
                state.notice?.let {
                    snackbar.showSnackbar(it.message)
                    model.dismissNotice(it.id)
                }
            }
            LaunchedEffect(destination) { model.recordUserAction("screen.opened", "destination=$destination") }
            LaunchedEffect(destination) {
                if (destination == 3) {
                    destination = 0
                    lyricsMode = true
                }
            }
            BackHandler(enabled = lyricsMode && state.profile != null) { closeLyrics() }
            BackHandler(enabled = nowPlayingOpen && !lyricsMode && state.profile != null) { nowPlayingOpen = false }
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val wide = maxWidth >= 720.dp
                val compactNavigation = maxWidth < 400.dp || LocalDensity.current.fontScale >= 1.5f
                Scaffold(
                    bottomBar = {
                        Column {
                            if (snackbar.currentSnackbarData != null) {
                                SnackbarHost(snackbar)
                            }
                            if (state.profile != null && !lyricsMode && !nowPlayingOpen && state.snapshot?.current != null) {
                                MiniPlayerBar(model, state, onOpen = { nowPlayingOpen = true })
                            }
                            if (!wide && state.profile != null && !lyricsMode && !nowPlayingOpen) {
                                NavigationBar {
                                    destinations.forEach { item ->
                                        NavigationBarItem(
                                            selected = destination == item.id,
                                            onClick = {
                                                destination = item.id
                                                nowPlayingOpen = false
                                            },
                                            icon = {
                                                Icon(
                                                    cadenzaVector(item.icon),
                                                    contentDescription = item.label.takeIf { compactNavigation },
                                                )
                                            },
                                            label = if (compactNavigation) null else ({ Text(item.label) }),
                                        )
                                    }
                                }
                            }
                        }
                    },
                ) { outerPadding ->
                    Box(Modifier.fillMaxSize().padding(outerPadding)) {
                        if (lyricsMode && state.profile != null) {
                            LyricsScreen(model, state, onExit = ::closeLyrics)
                        } else if (nowPlayingOpen && state.profile != null) {
                            PlayingScreen(
                                model,
                                state,
                                wide,
                                restoreLyricsFocus,
                                onLyricsFocusRestored = { restoreLyricsFocus = false },
                                onOpenLyrics = { lyricsMode = true },
                            )
                        } else {
                            Column(Modifier.fillMaxSize()) {
                                Row(Modifier.weight(1f)) {
                                    if (wide && state.profile != null) {
                                        NavigationRail(Modifier.fillMaxHeight().width(104.dp)) {
                                            destinations.forEach { item ->
                                                NavigationRailItem(
                                                    selected = destination == item.id,
                                                    onClick = {
                                                        destination = item.id
                                                        nowPlayingOpen = false
                                                    },
                                                    icon = { Icon(cadenzaVector(item.icon), contentDescription = null) },
                                                    label = { Text(item.label) },
                                                )
                                            }
                                        }
                                    }
                                    Box(Modifier.weight(1f).fillMaxHeight()) {
                                        if (state.profile == null) {
                                            PairingScreen(model, state)
                                        } else {
                                            screenState.SaveableStateProvider(destination) {
                                                when (destination) {
                                                    0 ->
                                                        HomeScreen(
                                                            model,
                                                            state,
                                                            wide,
                                                            restoreLyricsFocus,
                                                            onLyricsFocusRestored = { restoreLyricsFocus = false },
                                                            onOpenLyrics = { lyricsMode = true },
                                                        )
                                                    1 -> SearchScreen(model, state)
                                                    2 -> QueueScreen(model, state)
                                                    4 -> AnalyticsScreen(model, state)
                                                    else -> SettingsScreen(model, state, installUpdate)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        state.prompt?.let { prompt ->
            AlertDialog(
                onDismissRequest = model::dismissPrompt,
                title = { Text(prompt.title) },
                text = { Text(prompt.message) },
                confirmButton = { TextButton(onClick = model::dismissPrompt) { Text("OK") } },
            )
        }
    }
}
