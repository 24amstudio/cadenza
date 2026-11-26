package app.cadenza.remote.tv

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.net.toUri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import app.cadenza.remote.ui.lyrics.activeLineIndices
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

/** The 10-foot stage. It is driven by a TV remote, so every control has a key, and the picture stays on OLED-safe colors. */
@Composable
internal fun TvStageScreen(
    model: TvStageModel,
    onExit: () -> Unit,
) {
    val state by model.state.collectAsState()
    var address by remember { mutableStateOf(model.savedAddress.orEmpty()) }
    var addressError by remember { mutableStateOf(false) }
    var lipSync by remember { mutableStateOf(model.lipSyncOffsetMs) }
    BackHandler(onBack = onExit)
    Box(
        modifier =
            Modifier
                .fillMaxSize()
                .background(Color.Black)
                .onPreviewKeyEvent { event ->
                    if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                    when (event.key) {
                        Key.DirectionCenter, Key.Enter, Key.MediaPlayPause -> model.sendCommand(togglePlayback(state.playing))
                        Key.MediaPlay -> model.sendCommand("playback.resume")
                        Key.MediaPause -> model.sendCommand("playback.pause")
                        Key.DirectionRight, Key.MediaNext -> model.sendCommand("playback.skip")
                        Key.DirectionLeft, Key.MediaPrevious -> model.sendCommand("playback.previous")
                        Key.DirectionUp -> lipSync = nudge(model, lipSync, 10)
                        Key.DirectionDown -> lipSync = nudge(model, lipSync, -10)
                        else -> return@onPreviewKeyEvent false
                    }
                    true
                },
        contentAlignment = Alignment.Center,
    ) {
        when {
            state.phase == TvStageState.Phase.PAIRING -> PairingPanel(model.savedAddress, state.pin)
            state.suite == null && state.phase == TvStageState.Phase.OFFLINE ->
                StatusPanel(
                    "Reconnecting to Cadenza",
                    "This TV reconnects when the Mac is back on the network.",
                )
            state.suite == null && model.savedAddress == null ->
                AddressPanel(
                    address = address,
                    error = addressError,
                    onAddress = { address = it },
                    onConnect = {
                        addressError = !model.connect(address)
                    },
                )
            state.suite == null -> StatusPanel("Waiting for music", "Play something on your Mac to start.")
            else -> NowPlaying(state, lipSync)
        }
    }
}

private fun togglePlayback(playing: Boolean): String = if (playing) "playback.pause" else "playback.resume"

private fun nudge(
    model: TvStageModel,
    current: Int,
    step: Int,
): Int {
    val next = (current + step).coerceIn(0, TvStagePrefs.MAX_LIP_SYNC_MS)
    model.setLipSyncOffsetMs(next)
    return next
}

@Composable
private fun PairingPanel(
    address: String?,
    pin: String?,
) {
    val approvalUrl = if (address != null && pin != null) TvStageConfig.approvalUrl(address, pin) else null
    val qr = remember(approvalUrl) { approvalUrl?.let { pairingQrBitmap(it, QR_PIXELS) } }
    Row(horizontalArrangement = Arrangement.spacedBy(72.dp), verticalAlignment = Alignment.CenterVertically) {
        qr?.let {
            Image(
                bitmap = it.asImageBitmap(),
                contentDescription = "QR code that opens Cadenza to approve this TV",
                modifier = Modifier.size(360.dp),
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Text("Approve this TV", color = Color.White, fontSize = 40.sp, fontWeight = FontWeight.SemiBold)
            Text(pin.orEmpty(), color = Color.White, fontSize = 128.sp, fontWeight = FontWeight.Bold)
            Text(
                "Scan the code with a phone, or enter this PIN in Cadenza on your Mac.",
                color = Color.White.copy(alpha = 0.7f),
                fontSize = 22.sp,
                modifier = Modifier.widthIn(max = 520.dp),
            )
        }
    }
}

private const val QR_PIXELS = 512

@Composable
private fun StatusPanel(
    title: String,
    detail: String,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, color = Color.White, fontSize = 40.sp, fontWeight = FontWeight.SemiBold)
        Text(detail, color = Color.White.copy(alpha = 0.7f), fontSize = 22.sp)
    }
}

@Composable
private fun AddressPanel(
    address: String,
    error: Boolean,
    onAddress: (String) -> Unit,
    onConnect: () -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.widthIn(max = 720.dp).fillMaxWidth().padding(24.dp),
    ) {
        Text("Connect to Cadenza", color = Color.White, fontSize = 36.sp, fontWeight = FontWeight.SemiBold)
        Text(
            "Type the TV address shown in Cadenza Host settings, such as 192.168.1.10:8765.",
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 20.sp,
        )
        OutlinedTextField(
            value = address,
            onValueChange = onAddress,
            singleLine = true,
            isError = error,
            label = { Text("Host address") },
            modifier = Modifier.fillMaxWidth(),
        )
        if (error) Text("Use a local address that starts with the Host's IP address.", color = Color(0xFFFF8A8A))
        Button(onClick = onConnect) { Text("Connect") }
    }
}

@Composable
private fun NowPlaying(
    state: TvStageState,
    lipSync: Int,
) {
    val suite = state.suite ?: return
    val artwork = rememberRemoteBitmap(suite.artworkUrl)
    var active by remember { mutableStateOf(emptyList<Int>()) }
    LaunchedEffect(state, lipSync) {
        while (isActive) {
            val position = state.positionAt(SystemClock.elapsedRealtime()) - lipSync - (state.video?.userOffsetMs ?: 0L)
            val indices = activeLineIndices(suite.lines, position)
            if (indices != active) active = indices
            delay(FRAME_MS)
        }
    }
    Box(modifier = Modifier.fillMaxSize()) {
        artwork?.let { bitmap ->
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)),
            )
        }
        state.video?.let { video -> KaraokeVideo(video.mediaUrl, video.subtitleUrl) }
        Column(
            modifier = Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(horizontal = 64.dp, vertical = 48.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(suite.title, color = Color.White, fontSize = 40.sp, fontWeight = FontWeight.SemiBold)
            Text(suite.artist, color = Color.White.copy(alpha = 0.7f), fontSize = 24.sp)
            suite.quality?.let { Text(it, color = Color.White, fontSize = 18.sp) }
            active.forEach { index ->
                suite.lines.getOrNull(index)?.let { line ->
                    Text(line.text, color = Color.White, fontSize = 56.sp, fontWeight = FontWeight.Bold)
                    line.translation?.let { Text(it, color = Color.White.copy(alpha = 0.8f), fontSize = 28.sp) }
                }
            }
        }
    }
}

@Composable
private fun KaraokeVideo(
    mediaUrl: String,
    subtitleUrl: String,
) {
    val context = LocalContext.current
    val player =
        remember(mediaUrl) {
            ExoPlayer.Builder(context).build().apply {
                val subtitle =
                    MediaItem.SubtitleConfiguration
                        .Builder(subtitleUrl.toUri())
                        .setMimeType(MimeTypes.TEXT_VTT)
                        .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                        .build()
                setMediaItem(
                    MediaItem
                        .Builder()
                        .setUri(mediaUrl)
                        .setSubtitleConfigurations(listOf(subtitle))
                        .build(),
                )
                prepare()
                playWhenReady = true
            }
        }
    DisposableEffect(player) { onDispose { player.release() } }
    AndroidView(factory = {
        PlayerView(it).apply {
            this.player = player
            useController = false
        }
    }, modifier = Modifier.fillMaxSize())
}

/** Downloads one LAN artwork image. A failure leaves the stage on its black background. */
@Composable
private fun rememberRemoteBitmap(url: String?): Bitmap? {
    var bitmap by remember(url) { mutableStateOf<Bitmap?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(url) {
        if (url == null) return@LaunchedEffect
        scope.launch {
            bitmap = withContext(Dispatchers.IO) { fetchBitmap(url) }
        }
    }
    return bitmap
}

private val artworkClient = OkHttpClient()

private fun fetchBitmap(url: String): Bitmap? =
    runCatching {
        artworkClient.newCall(Request.Builder().url(url).build()).execute().use { response ->
            if (!response.isSuccessful) return null
            BitmapFactory.decodeStream(response.body.byteStream())
        }
    }.getOrNull()

private const val FRAME_MS = 16L
