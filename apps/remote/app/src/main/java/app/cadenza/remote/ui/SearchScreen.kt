package app.cadenza.remote.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AssistChip
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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.Song
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.search.RankedSong
import app.cadenza.remote.search.SearchSignals
import app.cadenza.remote.search.SearchSuggestion
import app.cadenza.remote.search.SongSignals
import app.cadenza.remote.search.SuggestionKind
import app.cadenza.remote.search.composeSuggestions
import app.cadenza.remote.search.rankSearch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(
    model: RemoteModel,
    state: RemoteState,
) {
    var query by rememberSaveable { mutableStateOf("") }
    // Results are ranked against the submitted query, so the list does not reorder while the user is still typing.
    var submitted by rememberSaveable { mutableStateOf("") }
    var library by rememberSaveable { mutableStateOf(false) }
    var focused by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<Song?>(null) }
    val focusManager = LocalFocusManager.current
    val signals = remember(state.favorites, state.statistics) { SearchSignals(state.favorites, state.statistics) }
    val correction = state.correctedQuery.takeIf { state.correctedResults.isNotEmpty() }
    val ranked =
        remember(state.results, state.correctedResults, submitted, correction, signals) {
            rankSearch(submitted, state.results, correction, state.correctedResults, signals)
        }
    val suggestions =
        remember(query, state.recentSearches, state.suggestedTerms, state.suggestedSongs, state.favorites, state.statistics) {
            composeSuggestions(
                query,
                state.recentSearches,
                state.suggestedTerms,
                state.favorites,
                state.statistics,
                state.suggestedSongs,
            )
        }

    fun open(song: Song) {
        selected = song
        model.prepare(song)
    }

    fun submit(text: String) {
        if (text.isBlank()) return
        query = text
        submitted = text
        focusManager.clearFocus()
        model.search(text, library)
    }

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
                    OutlinedTextField(
                        query,
                        { text ->
                            query = text.take(200)
                            model.suggest(query)
                        },
                        Modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused },
                        label = { Text("Song, artist, or album") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(onSearch = { submit(query) }),
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        FilterChip(selected = !library, onClick = { library = false }, label = { Text("Apple Music") })
                        FilterChip(selected = library, onClick = { library = true }, label = { Text("Host library") })
                    }
                    if (focused && query.isNotBlank() && suggestions.isNotEmpty()) {
                        SuggestionList(suggestions) { suggestion ->
                            val song = suggestion.song
                            if (song != null) open(song) else submit(suggestion.text)
                        }
                    } else if (query.isBlank() && state.recentSearches.isNotEmpty()) {
                        RecentSearches(state.recentSearches) { submit(it) }
                    }
                    ActionButton("Search", pending = state.searching, enabled = state.connected && query.isNotBlank()) {
                        submit(query)
                    }
                }
            }
            when {
                state.searching -> LoadingScreen("Searching Cadenza Host…")
                ranked.isEmpty() -> NoResults(submitted)
                else -> RankedResults(ranked, correction, Modifier.weight(1f)) { open(it) }
            }
        }
    }
    selected?.let { song ->
        ModalBottomSheet(onDismissRequest = { selected = null }) {
            SongActions(model, state, song)
        }
    }
}

@Composable
private fun RecentSearches(
    recent: List<String>,
    onChoose: (String) -> Unit,
) {
    Text("Recent searches", style = MaterialTheme.typography.labelLarge)
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        recent.take(RECENT_LIMIT).forEach { text ->
            AssistChip(onClick = { onChoose(text) }, label = { Text(text, maxLines = 1) })
        }
    }
}

@Composable
private fun SuggestionList(
    suggestions: List<SearchSuggestion>,
    onChoose: (SearchSuggestion) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        suggestions.forEach { suggestion ->
            Row(
                Modifier.fillMaxWidth().clickable { onChoose(suggestion) }.padding(vertical = 10.dp, horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.fillMaxWidth()) {
                    Text(
                        suggestion.song?.let { "${it.title} · ${it.artist}" } ?: suggestion.text,
                        style = MaterialTheme.typography.bodyLarge,
                        maxLines = 1,
                    )
                    Text(
                        suggestionLabel(suggestion.kind),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

private fun suggestionLabel(kind: SuggestionKind): String =
    when (kind) {
        SuggestionKind.Recent -> "Recent search"
        SuggestionKind.Term -> "Apple Music suggestion"
        SuggestionKind.Favorite -> "Favorite"
        SuggestionKind.Played -> "Played on this Remote"
        SuggestionKind.Song -> "Apple Music song"
    }

@Composable
private fun NoResults(submitted: String) {
    Text(
        if (submitted.isBlank()) "Search results will appear here." else "No matching songs yet.",
        style = MaterialTheme.typography.bodyLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun RankedResults(
    ranked: List<RankedSong>,
    correction: String?,
    modifier: Modifier,
    onChoose: (Song) -> Unit,
) {
    LazyColumn(modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        correction?.let {
            item(key = "correction") {
                Text(
                    "Also showing songs for \"$it\"",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        item(key = "best-match") {
            Text("Best match", style = MaterialTheme.typography.labelLarge)
        }
        items(ranked.take(1), key = { it.song.source + ":" + it.song.id }) { entry ->
            SongRow(entry, prominent = true, onChoose = onChoose)
        }
        if (ranked.size > 1) {
            item(key = "more-songs") {
                Text("More songs", style = MaterialTheme.typography.labelLarge)
            }
        }
        items(ranked.drop(1), key = { it.song.source + ":" + it.song.id }) { entry ->
            SongRow(entry, prominent = false, onChoose = onChoose)
        }
    }
}

@Composable
private fun SongRow(
    entry: RankedSong,
    prominent: Boolean,
    onChoose: (Song) -> Unit,
) {
    val song = entry.song
    Surface(
        onClick = { onChoose(song) },
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        color = if (prominent) MaterialTheme.colorScheme.surfaceContainerHigh else MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Row(
            Modifier.padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Artwork(song.artworkUrl, Modifier.size(if (prominent) 88.dp else 64.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    song.title,
                    style = if (prominent) MaterialTheme.typography.headlineSmall else MaterialTheme.typography.titleLarge,
                )
                Text(song.artist, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    listOf(song.album, duration(song.durationMs)).filter { it.isNotBlank() }.joinToString(" · "),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                badgeText(entry.signals)?.let {
                    Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}

private fun badgeText(signals: SongSignals): String? {
    val parts =
        listOfNotNull(
            "Favorite".takeIf { signals.favorite },
            when (signals.plays) {
                0L -> null
                1L -> "Played once"
                else -> "Played ${signals.plays} times"
            },
        )
    return parts.joinToString(" · ").ifEmpty { null }
}

private const val RECENT_LIMIT = 4
