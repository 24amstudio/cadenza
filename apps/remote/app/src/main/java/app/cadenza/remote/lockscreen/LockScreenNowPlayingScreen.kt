package app.cadenza.remote.lockscreen

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.cadenza.remote.playback.NowPlayingSnapshot
import app.cadenza.remote.ui.CadenzaIcon
import app.cadenza.remote.ui.MotionArtwork
import app.cadenza.remote.ui.cadenzaVector

/** The lock-screen surface. Transport goes through PlaybackMediaService, the same path the widget uses. */
@Composable
fun LockScreenNowPlayingScreen(
    snapshot: NowPlayingSnapshot?,
    lyricIndex: Int?,
    onControl: (String) -> Unit,
    onArtistTap: () -> Unit,
) {
    MaterialExpressiveTheme(colorScheme = darkColorScheme()) {
        val still = remember(snapshot?.artwork) { snapshot?.artwork?.let(::decodeStill) }
        val lyric = lyricIndex?.let { snapshot?.lyrics?.lines?.getOrNull(it) }
        val playing = snapshot?.playing == true
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            MotionArtwork(
                video = snapshot?.motion,
                playing = playing,
                modifier = Modifier.fillMaxSize(),
                fallback = {
                    still?.let {
                        Image(
                            bitmap = it,
                            contentDescription = null,
                            modifier = Modifier.fillMaxSize(),
                            contentScale = ContentScale.Crop,
                        )
                    }
                },
            )
            Column(
                Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    .background(Color.Black.copy(alpha = 0.45f))
                    .navigationBarsPadding()
                    .padding(horizontal = 24.dp, vertical = 20.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    snapshot?.title.orEmpty(),
                    style = MaterialTheme.typography.headlineMedium,
                    color = Color.White,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    snapshot?.artist.orEmpty(),
                    style = MaterialTheme.typography.titleMedium,
                    color = Color.White.copy(alpha = 0.8f),
                    modifier =
                        Modifier.clickable(role = Role.Button, onClickLabel = "Open artist", onClick = onArtistTap),
                )
                if (lyric != null && lyric.text.isNotBlank()) {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        lyric.text,
                        style = MaterialTheme.typography.titleLarge,
                        color = Color.White,
                        maxLines = 2,
                        textAlign = if (lyric.align == "end") TextAlign.End else TextAlign.Start,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Transport("Previous", CadenzaIcon.PREVIOUS, onClick = { onControl("previous") })
                    Transport(
                        if (playing) "Pause" else "Play",
                        if (playing) CadenzaIcon.PAUSE else CadenzaIcon.PLAY,
                        onClick = { onControl(if (playing) "pause" else "play") },
                    )
                    Transport("Next", CadenzaIcon.NEXT, onClick = { onControl("next") })
                }
            }
        }
    }
}

@Composable
private fun Transport(
    label: String,
    icon: CadenzaIcon,
    onClick: () -> Unit,
) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(56.dp).semantics { contentDescription = label },
    ) {
        Icon(cadenzaVector(icon), contentDescription = null, tint = Color.White)
    }
}

private fun decodeStill(bytes: ByteArray) = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
