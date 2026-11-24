package app.cadenza.remote.ui.browse

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.BrowseTarget
import app.cadenza.remote.data.Song
import app.cadenza.remote.model.RemoteState

// Makes an artist or album name open its page. A page the Host cannot address, or a Host without browsing, stays plain text.
@Composable
fun Modifier.browseLink(
    state: RemoteState,
    song: Song,
    label: String,
    target: (Song) -> BrowseTarget,
): Modifier {
    val navigator = LocalBrowseNavigator.current
    val destination = target(song)
    return if (canBrowse(state, destination)) {
        clickable(onClickLabel = label) { navigator.open(destination) }.padding(vertical = 6.dp)
    } else {
        this
    }
}
