package app.cadenza.remote.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.Song
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(
    model: RemoteModel,
    state: RemoteState,
) {
    var query by rememberSaveable { mutableStateOf("") }
    var library by rememberSaveable { mutableStateOf(false) }
    var selected by remember { mutableStateOf<Song?>(null) }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val compact = maxWidth < 600.dp
        Column(
            Modifier.fillMaxSize().padding(if (compact) 16.dp else 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            ScreenHeader("Search", state)
            Surface(
                Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.extraLarge,
                color = MaterialTheme.colorScheme.surfaceContainerLow,
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Find a song to control from Cadenza Remote.", style = MaterialTheme.typography.bodyLarge)
                    OutlinedTextField(
                        query,
                        { query = it.take(200) },
                        Modifier.fillMaxWidth(),
                        label = { Text("Song, artist, or album") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(onSearch = { model.search(query, library) }),
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        FilterChip(selected = !library, onClick = { library = false }, label = { Text("Apple Music") })
                        FilterChip(selected = library, onClick = { library = true }, label = { Text("Host library") })
                    }
                    ActionButton("Search", pending = state.searching, enabled = state.connected && query.isNotBlank()) {
                        model.search(query, library)
                    }
                }
            }
            when {
                state.searching -> LoadingScreen("Searching Cadenza Host…")
                state.results.isEmpty() ->
                    Text(
                        if (query.isBlank()) "Search results will appear here." else "No matching songs yet. Try another search.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                else ->
                    LazyColumn(
                        Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        items(state.results, key = { it.source + ":" + it.id }) { song ->
                            Surface(
                                modifier =
                                    Modifier.fillMaxWidth().clickable {
                                        selected = song
                                        model.prepare(song)
                                    },
                                shape = MaterialTheme.shapes.extraLarge,
                                color = MaterialTheme.colorScheme.surfaceContainer,
                            ) {
                                Row(
                                    Modifier.padding(14.dp),
                                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Artwork(song.artworkUrl, Modifier.size(64.dp))
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text(song.title, style = MaterialTheme.typography.titleLarge)
                                        Text(song.artist, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        Text(
                                            song.album + " · " + duration(song.durationMs),
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            }
                        }
                    }
            }
        }
    }
    selected?.let { song ->
        ModalBottomSheet(onDismissRequest = { selected = null }) {
            SongActions(model, state, song)
        }
    }
}
