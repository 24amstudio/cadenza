package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.LyricDocument
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.model.setLyricDelay

/**
 * The karaoke sync nudge for a music video's lyrics. It moves the lyrics half a second at a time, or lines the first line
 * up with the sound now. The nudge is kept on the Host for this track.
 */
@Composable
internal fun LyricNudgePill(
    model: RemoteModel,
    state: RemoteState,
    document: LyricDocument?,
    rawPositionMs: Long,
    modifier: Modifier = Modifier,
) {
    val current = state.snapshot?.current ?: return
    val firstLine = document?.lines?.firstOrNull() ?: return
    if (!current.song.isMusicVideo) return
    val delay = state.lyricDelayMs
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        OutlinedButton(onClick = { model.setLyricDelay(delay - 500) }, enabled = state.connected) { Text("-0.5 s") }
        OutlinedButton(onClick = { model.setLyricDelay(delay + 500) }, enabled = state.connected) { Text("+0.5 s") }
        OutlinedButton(
            onClick = { model.setLyricDelay((rawPositionMs - firstLine.startMs).toInt()) },
            enabled = state.connected,
        ) { Text("Sync First Line") }
        Spacer(Modifier.width(4.dp))
    }
}
