package app.cadenza.remote.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldRole
import androidx.compose.material3.adaptive.layout.ThreePaneScaffoldDestinationItem
import androidx.compose.material3.adaptive.navigation.NavigableListDetailPaneScaffold
import androidx.compose.material3.adaptive.navigation.rememberListDetailPaneScaffoldNavigator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.RemoteModel
import app.cadenza.remote.RemoteState
import app.cadenza.remote.data.Song
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun HomeScreen(
    model: RemoteModel,
    state: RemoteState,
    wide: Boolean,
    restoreLyricsFocus: Boolean,
    onLyricsFocusRestored: () -> Unit,
    onOpenLyrics: () -> Unit,
) {
    val navigator =
        rememberListDetailPaneScaffoldNavigator<String>(
            initialDestinationHistory =
                listOf(
                    ThreePaneScaffoldDestinationItem(ListDetailPaneScaffoldRole.List),
                    ThreePaneScaffoldDestinationItem(ListDetailPaneScaffoldRole.Detail, "playing"),
                ),
        )
    val scope = rememberCoroutineScope()
    var favorites by rememberSaveable { mutableStateOf(false) }
    val selected = navigator.currentDestination?.contentKey ?: "playing"
    val songs =
        if (favorites) {
            state.favorites
        } else {
            state.snapshot
                ?.queue
                .orEmpty()
                .map { it.song }
        }
    val selectedSong =
        state.favorites.firstOrNull { "favorite:" + it.source + ":" + it.id == selected }
            ?: state.snapshot
                ?.queue
                ?.firstOrNull { it.id == selected }
                ?.song

    fun select(
        key: String,
        song: Song?,
    ) {
        if (song != null && state.connected) model.prepare(song)
        scope.launch { navigator.navigateTo(ListDetailPaneScaffoldRole.Detail, key) }
    }

    NavigableListDetailPaneScaffold(
        navigator = navigator,
        listPane = {
            AnimatedPane {
                Column(
                    Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    LibraryHeading(state)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        FilterChip(
                            selected = !favorites,
                            onClick = { favorites = false },
                            label = { Text("Up next · ${state.snapshot?.queue?.size ?: 0}") },
                        )
                        FilterChip(
                            selected = favorites,
                            onClick = { favorites = true },
                            label = { Text("Favorites · ${state.favorites.size}") },
                        )
                    }
                    if (state.snapshot?.current != null) {
                        NowPlayingCard(state, Modifier.fillMaxWidth().clickable { select("playing", null) })
                    }
                    if (favorites && state.unreadableFavorites > 0) {
                        UnreadableFavoritesCard(state.unreadableFavorites)
                    }
                    if (songs.isEmpty()) {
                        EmptyCollectionCard(favorites)
                    } else {
                        LazyColumn(
                            modifier = Modifier.weight(1f).fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            items(songs.withIndex().toList(), key = { (index, song) ->
                                "$index:${song.source}:${song.id}"
                            }) { (index, song) ->
                                val itemKey =
                                    if (favorites) {
                                        "favorite:" + song.source + ":" + song.id
                                    } else {
                                        state.snapshot
                                            ?.queue
                                            ?.getOrNull(index)
                                            ?.id
                                            .orEmpty()
                                    }
                                LibrarySongRow(
                                    song = song,
                                    favorites = favorites,
                                    selected = itemKey == selected,
                                    detail =
                                        if (favorites) {
                                            songDetails(song)
                                        } else {
                                            state.snapshot
                                                ?.queue
                                                ?.getOrNull(index)
                                                ?.let {
                                                    it.requesterName + " · Wait ≈ " + duration(it.estimatedWaitMs)
                                                }.orEmpty()
                                        },
                                    onClick = { select(itemKey, song) },
                                )
                            }
                        }
                    }
                }
            }
        },
        detailPane = {
            AnimatedPane {
                Column(Modifier.fillMaxSize()) {
                    if (!wide) {
                        TextButton(onClick = { scope.launch { navigator.navigateTo(ListDetailPaneScaffoldRole.List) } }) {
                            Icon(cadenzaVector(CadenzaIcon.BACK), contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.size(8.dp))
                            Text("Queue and Favorites")
                        }
                    }
                    when {
                        selected == "playing" ->
                            PlayingScreen(
                                model,
                                state,
                                wide,
                                restoreLyricsFocus,
                                onLyricsFocusRestored,
                                onOpenLyrics,
                            )
                        selectedSong != null -> SongActions(model, state, selectedSong, Modifier.fillMaxSize())
                        else -> EmptySelectionCard(Modifier.fillMaxSize())
                    }
                }
            }
        },
    )
}

@Composable
private fun LibraryHeading(state: RemoteState) {
    val count = state.snapshot?.queue?.size ?: 0
    val remaining = state.snapshot?.totalRemainingMs?.let(::duration)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text("Library", style = MaterialTheme.typography.headlineLarge)
            Text(
                if (remaining == null) "$count requests from Cadenza Host" else "$count requests • $remaining total",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        val connection =
            when {
                state.connected -> "Connected"
                state.connecting -> "Connecting"
                else -> "Offline"
            }
        Surface(
            shape = CircleShape,
            color = if (state.connected) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh,
        ) {
            Text(
                connection,
                Modifier.padding(horizontal = 14.dp, vertical = 9.dp),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
private fun NowPlayingCard(
    state: RemoteState,
    modifier: Modifier,
) {
    val current = state.snapshot?.current
    Surface(modifier, shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.primaryContainer) {
        Row(
            Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surface.copy(alpha = 0.72f)) {
                Box(Modifier.size(56.dp), contentAlignment = Alignment.Center) {
                    Icon(
                        cadenzaVector(CadenzaIcon.MUSIC),
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                        modifier = Modifier.size(27.dp),
                    )
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Now playing", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onPrimaryContainer)
                Text(
                    current?.song?.title ?: "Nothing is playing",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
                Text(
                    current?.song?.artist ?: "Start a song in Music from Cadenza Host",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
                if (state.snapshot?.mixing == true) {
                    Text(
                        state.snapshot.incoming?.let { "AutoMix → ${it.title}" } ?: "AutoMix transition",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
            }
            Icon(
                cadenzaVector(CadenzaIcon.NEXT),
                contentDescription = "Open current song",
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
            )
        }
    }
}

@Composable
private fun LibrarySongRow(
    song: Song,
    favorites: Boolean,
    selected: Boolean,
    detail: String,
    onClick: () -> Unit,
) {
    Surface(
        Modifier.fillMaxWidth().clickable(onClick = onClick),
        shape = MaterialTheme.shapes.extraLarge,
        color = if (selected) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Artwork(song.artworkUrl, Modifier.size(60.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(song.title, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
                Text(song.artist, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (detail.isNotBlank()) {
                    Text(detail, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (selected) {
                Icon(
                    cadenzaVector(CadenzaIcon.PLAY),
                    contentDescription = if (favorites) "Selected favorite" else "Selected queue request",
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}

@Composable
private fun EmptyCollectionCard(favorites: Boolean) {
    Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Row(
            Modifier.fillMaxWidth().padding(20.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                cadenzaVector(if (favorites) CadenzaIcon.MUSIC else CadenzaIcon.QUEUE),
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(28.dp),
            )
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(if (favorites) "Your Favorites are ready" else "Your queue is clear", style = MaterialTheme.typography.titleMedium)
                Text(
                    if (favorites) {
                        "Save a song from Search or Now playing."
                    } else {
                        "Search Apple Music and add a request."
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun UnreadableFavoritesCard(count: Int) {
    Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.errorContainer) {
        Text(
            "$count saved ${if (count == 1) "song could" else "songs could"} not be read. Their stored data is preserved.",
            Modifier.fillMaxWidth().padding(14.dp),
            color = MaterialTheme.colorScheme.onErrorContainer,
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}

@Composable
private fun EmptySelectionCard(modifier: Modifier) {
    Box(modifier.padding(24.dp), contentAlignment = Alignment.Center) {
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Text(
                "This song is no longer in the queue or Favorites.",
                Modifier.padding(24.dp),
                style = MaterialTheme.typography.titleMedium,
            )
        }
    }
}

private fun songDetails(song: Song): String =
    listOf(song.album.takeIf(String::isNotBlank), song.durationMs?.let(::duration))
        .filterNotNull()
        .joinToString(" · ")
