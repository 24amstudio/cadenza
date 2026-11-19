package app.cadenza.remote.ui.browse

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.BrowseItem
import app.cadenza.remote.ui.Artwork
import app.cadenza.remote.ui.CadenzaIcon
import app.cadenza.remote.ui.cadenzaVector
import app.cadenza.remote.ui.duration

@Composable
internal fun BrowseTrackRow(
    item: BrowseItem.Track,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val song = item.song
    BrowseRow(
        title = song.title,
        subtitle = listOf(song.artist, song.album).filter(String::isNotBlank).distinct().joinToString(" · "),
        trailing = song.durationMs?.let(::duration),
        artworkUrl = song.artworkUrl,
        modifier = modifier,
        onClick = onClick,
    )
}

@Composable
internal fun BrowseCollectionRow(
    item: BrowseItem.Collection,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
) {
    BrowseRow(
        title = item.title,
        subtitle = item.subtitle.orEmpty(),
        trailing = null,
        artworkUrl = item.artworkUrl,
        modifier = modifier,
        selected = selected,
        chevron = true,
        onClick = onClick,
    )
}

@Composable
private fun BrowseRow(
    title: String,
    subtitle: String,
    trailing: String?,
    artworkUrl: String?,
    modifier: Modifier,
    selected: Boolean = false,
    chevron: Boolean = false,
    onClick: () -> Unit,
) {
    Surface(
        modifier.fillMaxWidth().clickable(onClick = onClick),
        shape = MaterialTheme.shapes.large,
        color = if (selected) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Row(
            Modifier.fillMaxWidth().padding(10.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Artwork(artworkUrl, Modifier.size(56.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (subtitle.isNotBlank()) {
                    Text(
                        subtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            trailing?.let {
                Text(it, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (chevron) {
                Icon(
                    cadenzaVector(CadenzaIcon.CHEVRON),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}
