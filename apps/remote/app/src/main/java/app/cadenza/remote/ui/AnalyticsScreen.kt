package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.SongStatistic
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState

@Composable
fun AnalyticsScreen(
    model: RemoteModel,
    state: RemoteState,
) {
    var sortByTime by rememberSaveable { mutableStateOf(false) }
    val totalPlays = state.statistics.sumOf { it.plays }
    val totalTime = state.statistics.sumOf { it.playedMs }
    val ordered =
        if (sortByTime) {
            state.statistics.sortedWith(compareByDescending<SongStatistic> { it.playedMs }.thenBy { it.title })
        } else {
            state.statistics.sortedWith(compareByDescending<SongStatistic> { it.plays }.thenBy { it.title })
        }
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp),
        contentPadding = PaddingValues(vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item { ScreenHeader("Your music", state) }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                MetricCard("Plays", totalPlays.toString(), Modifier.weight(1f))
                MetricCard("Listening", duration(totalTime), Modifier.weight(1f))
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = !sortByTime, onClick = { sortByTime = false }, label = { Text("Most played") })
                FilterChip(selected = sortByTime, onClick = { sortByTime = true }, label = { Text("Most time") })
            }
        }
        if (state.snapshot?.observationGap == true) {
            item {
                Text(
                    "Some listening time could not be observed while Host was unavailable.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (ordered.isEmpty()) {
            item {
                Surface(
                    Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.extraLarge,
                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                ) {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Your listening history will appear here", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Play a song from Search or Queue to start tracking plays on this Remote.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        } else {
            item { Text("Songs", style = MaterialTheme.typography.titleLarge) }
            items(ordered, key = { it.source + ":" + it.songId }) { item ->
                StatisticCard(model, state, item, ordered.maxOf { it.plays }.coerceAtLeast(1))
            }
        }
    }
}

@Composable
private fun MetricCard(label: String, value: String, modifier: Modifier = Modifier) {
    Surface(modifier, shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.primaryContainer) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, color = MaterialTheme.colorScheme.onPrimaryContainer)
            Text(value, style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.onPrimaryContainer)
        }
    }
}

@Composable
private fun StatisticCard(model: RemoteModel, state: RemoteState, item: SongStatistic, maximumPlays: Long) {
    val song = Song(source = item.source, id = item.songId, title = item.title, artist = item.artist)
    val saved = state.favorites.any { it.identity == song.identity }
    Surface(
        Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(item.title, style = MaterialTheme.typography.titleMedium)
                    Text(item.artist, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                FavoriteIconButton(model, state, song)
            }
            Text(
                "${item.plays} ${if (item.plays == 1L) "play" else "plays"} · ${duration(item.playedMs)} listened",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            LinearProgressIndicator(
                progress = { item.plays.toFloat() / maximumPlays },
                modifier = Modifier.fillMaxWidth(),
            )
            if (saved) {
                Text("In Favorites", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
            }
        }
    }
}
