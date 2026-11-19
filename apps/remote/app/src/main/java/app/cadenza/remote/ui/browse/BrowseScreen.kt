package app.cadenza.remote.ui.browse

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldRole
import androidx.compose.material3.adaptive.layout.PaneAdaptedValue
import androidx.compose.material3.adaptive.navigation.NavigableListDetailPaneScaffold
import androidx.compose.material3.adaptive.navigation.rememberListDetailPaneScaffoldNavigator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.BrowseItem
import app.cadenza.remote.data.BrowseTarget
import app.cadenza.remote.model.BrowseLoad
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.model.browse
import app.cadenza.remote.model.cancelBrowse
import app.cadenza.remote.ui.ActionButton
import app.cadenza.remote.ui.CadenzaIcon
import app.cadenza.remote.ui.cadenzaVector
import kotlinx.coroutines.launch

// The page on top of the browse stack, shown in place of the current tab. Back returns to the page or tab beneath it.
@Composable
fun BrowseScreen(
    model: RemoteModel,
    state: RemoteState,
    target: BrowseTarget,
    onBack: () -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        if (target.kind != "playlists") {
            BrowseTopBar(target.title, onBack)
            BrowsePageContent(model, state, target, Modifier.weight(1f))
        } else {
            PlaylistsPane(model, state, onBack)
        }
    }
}

@Composable
private fun BrowseTopBar(
    title: String,
    onBack: () -> Unit,
) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack) { Icon(cadenzaVector(CadenzaIcon.BACK), contentDescription = "Back") }
        Text(title, style = MaterialTheme.typography.titleLarge, maxLines = 1)
    }
}

// Playlists browse as a list with the chosen playlist beside it on a tablet, and one after the other on a phone.
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
private fun PlaylistsPane(
    model: RemoteModel,
    state: RemoteState,
    onBack: () -> Unit,
) {
    val target = BrowseTarget.playlists
    val navigator = rememberListDetailPaneScaffoldNavigator<String>()
    val scope = rememberCoroutineScope()
    LaunchedEffect(target.key, state.connected) { model.browse(target) }
    DisposableEffect(target.key) { onDispose { model.cancelBrowse(target) } }
    val selected = navigator.currentDestination?.contentKey
    NavigableListDetailPaneScaffold(
        navigator = navigator,
        listPane = {
            AnimatedPane {
                Column(Modifier.fillMaxSize()) {
                    BrowseTopBar("Playlists", onBack)
                    when (val load = state.browse[target.key]) {
                        is BrowseLoad.Ready -> {
                            val playlists =
                                load.page.sections
                                    .flatMap { it.items }
                                    .filterIsInstance<BrowseItem.Collection>()
                            PlaylistList(playlists, selected) { item ->
                                scope.launch { navigator.navigateTo(ListDetailPaneScaffoldRole.Detail, item.id) }
                            }
                        }
                        is BrowseLoad.Failed ->
                            PlaylistsMessage(load.message, retry = state.connected) { model.browse(target, refresh = true) }
                        else ->
                            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.Center) {
                                CircularProgressIndicator(Modifier.padding(32.dp))
                            }
                    }
                }
            }
        },
        detailPane = {
            AnimatedPane {
                if (selected == null) {
                    PlaylistsMessage("Choose a playlist to see its songs.", retry = false) {}
                } else {
                    val playlist = BrowseTarget("playlist", selected, title = "Playlist")
                    Column(Modifier.fillMaxSize()) {
                        if (navigator.scaffoldValue[ListDetailPaneScaffoldRole.List] == PaneAdaptedValue.Hidden) {
                            BrowseTopBar("Playlists") { scope.launch { navigator.navigateBack() } }
                        }
                        BrowsePageContent(model, state, playlist, Modifier.weight(1f))
                    }
                }
            }
        },
    )
}

@Composable
private fun PlaylistList(
    playlists: List<BrowseItem.Collection>,
    selected: String?,
    onOpen: (BrowseItem.Collection) -> Unit,
) {
    if (playlists.isEmpty()) {
        PlaylistsMessage("No playlists in Music yet.", retry = false) {}
        return
    }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding =
            androidx.compose.foundation.layout
                .PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items(playlists, key = { it.id }, contentType = { "playlist" }) { item ->
            BrowseCollectionRow(item, onClick = { onOpen(item) }, selected = item.id == selected)
        }
    }
}

@Composable
private fun PlaylistsMessage(
    message: String,
    retry: Boolean,
    onRetry: () -> Unit,
) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically),
    ) {
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Row(
                Modifier.padding(20.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    cadenzaVector(CadenzaIcon.PLAYLIST),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(28.dp),
                )
                Text(message, style = MaterialTheme.typography.titleMedium)
            }
        }
        if (retry) ActionButton("Try again", onClick = onRetry)
    }
}
