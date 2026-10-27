package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.RemoteState

@Composable
fun AnalyticsScreen(state: RemoteState) {
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        ScreenHeader("Your music", state)
        Text("Play counts and observed playback time for your requests. Stored only on this Remote.")
        if (state.snapshot?.observationGap == true) {
            Text("Some time could not be observed while Host was unavailable. Missing time is excluded.")
        }
        if (state.statistics.isEmpty()) {
            Text("No plays recorded yet", style = MaterialTheme.typography.headlineSmall)
            Text("A request counts after Music confirms that playback started and progressed.")
        }
        val maximum = state.statistics.maxOfOrNull { it.plays }?.coerceAtLeast(1) ?: 1
        LazyColumn(verticalArrangement = Arrangement.spacedBy(24.dp)) {
            itemsIndexed(state.statistics, key = { _, item -> item.source + ":" + item.songId }) { index, item ->
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text((index + 1).toString() + ". " + item.title, style = MaterialTheme.typography.titleLarge)
                    Text(item.artist, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        item.plays.toString() +
                            if (item.plays == 1L) " play · " + duration(item.playedMs) else " plays · " + duration(item.playedMs),
                    )
                    LinearProgressIndicator(progress = { item.plays.toFloat() / maximum }, modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }
}
