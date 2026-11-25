package app.cadenza.remote.ui.browse

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.BrowseItem
import app.cadenza.remote.data.BrowsePage
import app.cadenza.remote.data.BrowseSection
import app.cadenza.remote.data.BrowseTarget
import app.cadenza.remote.data.Song
import app.cadenza.remote.model.BrowseLoad
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.model.browse
import app.cadenza.remote.model.cancelBrowse
import app.cadenza.remote.model.requestArtistMotion
import app.cadenza.remote.ui.ActionButton
import app.cadenza.remote.ui.Artwork
import app.cadenza.remote.ui.CadenzaIcon
import app.cadenza.remote.ui.MotionArtwork
import app.cadenza.remote.ui.SongActions
import app.cadenza.remote.ui.cadenzaVector
import java.io.File

// One album, artist or playlist. The page loads when it opens, survives rotation through the model's short-lived cache,
// and cancels its Host request when it is left while still loading.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BrowsePageContent(
    model: RemoteModel,
    state: RemoteState,
    target: BrowseTarget,
    modifier: Modifier = Modifier,
) {
    val navigator = LocalBrowseNavigator.current
    var selected by remember(target.key) { mutableStateOf<Song?>(null) }
    val artistPage = (state.browse[target.key] as? BrowseLoad.Ready)?.page?.takeIf { it.kind == "artist" }
    val artistName = artistPage?.title
    val artistMotion = state.artistMotion?.takeIf { it.artistName == artistName }?.file
    LaunchedEffect(target.key, state.connected) { model.browse(target) }
    LaunchedEffect(artistName, state.connected) { artistName?.let { model.requestArtistMotion(it) } }
    DisposableEffect(target.key) { onDispose { model.cancelBrowse(target) } }
    Box(modifier.fillMaxSize()) {
        when (val load = state.browse[target.key]) {
            is BrowseLoad.Ready ->
                PageBody(load.page, target, artistMotion) { item ->
                    when (item) {
                        is BrowseItem.Track -> {
                            selected = item.song
                            if (!item.song.isMusicVideo) model.prepare(item.song)
                        }
                        is BrowseItem.Collection -> navigator.open(BrowseTarget.of(item))
                    }
                }
            is BrowseLoad.Failed ->
                PageMessage(target.title, load.message, actionLabel = "Try again", enabled = state.connected) {
                    model.browse(target, refresh = true)
                }
            else -> PageLoading(target.title)
        }
    }
    selected?.let { song ->
        ModalBottomSheet(onDismissRequest = { selected = null }) { SongActions(model, state, song) }
    }
}

@Composable
private fun PageLoading(title: String) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
    ) {
        CircularProgressIndicator()
        Text(if (title.isBlank()) "Loading…" else "Loading $title…", style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
private fun PageMessage(
    title: String,
    message: String,
    actionLabel: String,
    enabled: Boolean,
    onAction: () -> Unit,
) {
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(title.ifBlank { "This page" } + " is unavailable", style = MaterialTheme.typography.titleLarge)
                Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
                ActionButton(actionLabel, enabled = enabled, onClick = onAction)
            }
        }
    }
}

@Composable
private fun PageBody(
    page: BrowsePage,
    target: BrowseTarget,
    artistMotion: File?,
    onItem: (BrowseItem) -> Unit,
) {
    val sections = page.sections.filter { it.items.isNotEmpty() }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        if (maxWidth >= 840.dp) {
            Row(Modifier.fillMaxSize().padding(24.dp), horizontalArrangement = Arrangement.spacedBy(32.dp)) {
                PageHeader(page, target, artistMotion, Modifier.weight(0.38f).fillMaxHeight(), expanded = true)
                SectionList(sections, onItem, Modifier.weight(0.62f).fillMaxHeight(), emptyMessage(page))
            }
        } else {
            SectionList(
                sections,
                onItem,
                Modifier.fillMaxSize(),
                emptyMessage(page),
                header = { PageHeader(page, target, artistMotion, Modifier.fillMaxWidth(), expanded = false) },
            )
        }
    }
}

private fun emptyMessage(page: BrowsePage): String =
    when (page.kind) {
        "playlist" -> "This playlist has no songs."
        "playlists" -> "No playlists in Music yet."
        else -> "Nothing to show here yet."
    }

@Composable
private fun PageHeader(
    page: BrowsePage,
    target: BrowseTarget,
    artistMotion: File?,
    modifier: Modifier,
    expanded: Boolean,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (page.kind == "artist" && artistMotion != null) {
            // The artist's motion video fills a wide band with a bottom readability scrim. The still artwork stays
            // until the first frame, and under reduced motion, BLE, or constrained Host budget it stays for good.
            val scrimColor = MaterialTheme.colorScheme.surface
            Box(
                Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 9f)
                    .clip(MaterialTheme.shapes.extraLarge),
            ) {
                MotionArtwork(
                    artistMotion,
                    playing = true,
                    modifier = Modifier.fillMaxSize(),
                    fallback = { Artwork(page.artworkUrl, Modifier.fillMaxSize(), large = true) },
                )
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                0.35f to Color.Transparent,
                                1.0f to scrimColor.copy(alpha = 0.85f),
                            ),
                        ),
                )
            }
        } else if (page.kind != "playlists") {
            Artwork(
                page.artworkUrl,
                Modifier.widthIn(max = if (expanded) 320.dp else 220.dp).fillMaxWidth().aspectRatio(1f),
                large = true,
            )
        }
        Text(page.title.ifBlank { target.title }, style = MaterialTheme.typography.headlineMedium)
        page.subtitle?.let {
            Text(it, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        page.detail?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun SectionList(
    sections: List<BrowseSection>,
    onItem: (BrowseItem) -> Unit,
    modifier: Modifier,
    emptyMessage: String,
    header: (@Composable () -> Unit)? = null,
) {
    LazyColumn(
        modifier = modifier,
        contentPadding =
            androidx.compose.foundation.layout.PaddingValues(
                horizontal =
                    if (header ==
                        null
                    ) {
                        0.dp
                    } else {
                        20.dp
                    },
                vertical = 16.dp,
            ),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        header?.let { item(key = "header", contentType = "header") { it() } }
        if (sections.isEmpty()) {
            item(key = "empty", contentType = "empty") {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        cadenzaVector(CadenzaIcon.MUSIC),
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(24.dp),
                    )
                    Text(emptyMessage, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        for (section in sections) {
            item(key = "title:" + section.id, contentType = "title") {
                Text(
                    section.title,
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.padding(top = 10.dp),
                )
            }
            items(
                section.items.withIndex().toList(),
                key = { (index, item) -> section.id + ":" + index + ":" + itemKey(item) },
                contentType = { (_, item) -> if (item is BrowseItem.Track) "track" else "collection" },
            ) { (_, item) ->
                when (item) {
                    is BrowseItem.Track -> BrowseTrackRow(item, onClick = { onItem(item) })
                    is BrowseItem.Collection -> BrowseCollectionRow(item, onClick = { onItem(item) })
                }
            }
        }
    }
}

private fun itemKey(item: BrowseItem): String =
    when (item) {
        is BrowseItem.Track -> item.song.source + ":" + item.song.id
        is BrowseItem.Collection -> item.kind + ":" + item.id
    }
