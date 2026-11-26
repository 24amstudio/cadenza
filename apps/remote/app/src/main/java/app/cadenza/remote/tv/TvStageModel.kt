package app.cadenza.remote.tv

import android.app.Application
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.util.concurrent.TimeUnit

/**
 * The TV stage's connection and audio. It keeps one socket to the Host's stage channel, reconnects on a bounded backoff,
 * and feeds binary audio to the sink in order on a single background thread. Messages reduce into [state].
 */
internal class TvStageModel(
    application: Application,
) : AndroidViewModel(application) {
    private val prefs = TvStagePrefs(application)
    private val audioManager = application.getSystemService(AudioManager::class.java)
    private val client =
        OkHttpClient
            .Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .pingInterval(20, TimeUnit.SECONDS)
            .build()
    private val sink = TvAudioSink()
    private val audio: CoroutineDispatcher = Dispatchers.IO.limitedParallelism(1)
    private val _state = MutableStateFlow(TvStageState())
    val state: StateFlow<TvStageState> = _state.asStateFlow()
    private var socket: WebSocket? = null
    private var attempt = 0
    private var retry: Job? = null
    private var generation = -1L
    private var ac3Mode = false
    private var address: String? = prefs.address

    /** The Host address the stage uses, if one was saved. */
    val savedAddress: String? get() = address

    /** Saves [typed] as the Host address and connects. Returns false when it is not a plain LAN address. */
    fun connect(typed: String): Boolean {
        val url = TvStageConfig.socketUrl(typed) ?: return false
        address = typed.trim().trimEnd('/')
        prefs.address = address
        open(url)
        return true
    }

    /** Reconnects to the saved address, if there is one. A stage that is already open keeps its socket. */
    fun resume() {
        val saved = address ?: return
        if (socket == null) connect(saved)
    }

    fun sendCommand(action: String) {
        val text = TvStageMessages.command(action) ?: return
        socket?.send(text)
    }

    fun setLipSyncOffsetMs(value: Int) {
        prefs.lipSyncOffsetMs = value
    }

    val lipSyncOffsetMs: Int get() = prefs.lipSyncOffsetMs

    override fun onCleared() {
        retry?.cancel()
        socket?.close(NORMAL_CLOSE, null)
        socket = null
        sink.release()
        client.dispatcher.executorService.shutdown()
    }

    private fun open(url: String) {
        retry?.cancel()
        socket?.cancel()
        _state.update { TvStageState(phase = TvStageState.Phase.CONNECTING) }
        socket =
            client.newWebSocket(
                okhttp3.Request
                    .Builder()
                    .url(url)
                    .build(),
                listener,
            )
    }

    private fun scheduleRetry() {
        val delayMs = stageRetryDelayMs(attempt)
        attempt += 1
        retry =
            viewModelScope.launch {
                delay(delayMs)
                address?.let { if (socket == null) connect(it) }
            }
    }

    private fun profileJson(): String {
        val codecs = mutableListOf("pcm")
        if (supportsAc3()) codecs += "ac-3"
        return TvStageMessages.profile(
            receiverId = prefs.receiverId,
            displayName = "Cadenza TV",
            channels = if (codecs.contains("ac-3")) 6 else 2,
            codecs = codecs,
            lipSyncOffsetMs = prefs.lipSyncOffsetMs,
            token = prefs.token,
        )
    }

    private fun supportsAc3(): Boolean {
        val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS).orEmpty()
        return devices.any { device: AudioDeviceInfo -> TvAudioSink.supportsAc3(device.encodings.toList()) }
    }

    private val listener =
        object : WebSocketListener() {
            override fun onOpen(
                webSocket: WebSocket,
                response: Response,
            ) {
                attempt = 0
                if (prefs.token != null) _state.update { it.copy(phase = TvStageState.Phase.READY) }
                webSocket.send(profileJson())
            }

            override fun onMessage(
                webSocket: WebSocket,
                text: String,
            ) {
                val message = TvStageMessages.parse(text) ?: return
                if (message is TvStageMessage.Accepted) prefs.token = message.receiverToken
                _state.update { it.reduce(message, SystemClock.elapsedRealtime()) }
            }

            override fun onMessage(
                webSocket: WebSocket,
                bytes: ByteString,
            ) {
                val payload = bytes.toByteArray()
                viewModelScope.launch(audio) { playFrame(payload) }
            }

            override fun onClosed(
                webSocket: WebSocket,
                code: Int,
                reason: String,
            ) {
                closed(webSocket)
            }

            override fun onFailure(
                webSocket: WebSocket,
                t: Throwable,
                response: Response?,
            ) {
                closed(webSocket)
            }
        }

    private fun closed(webSocket: WebSocket) {
        if (socket !== webSocket) return
        socket = null
        _state.update { it.disconnected() }
        scheduleRetry()
    }

    private fun playFrame(bytes: ByteArray) {
        val frame = runCatching { StageFrameDecoder.decode(bytes) }.getOrNull() ?: return
        when (frame) {
            is StageFrame.InitSegment -> {
                ac3Mode = frame.codec == StageFrameDecoder.CODEC_AC3_FMP4
                sink.configure(frame.codec, frame.channels, frame.sampleRate)
            }
            is StageFrame.Flush -> {
                generation = frame.generationSeq
                sink.flush()
            }
            is StageFrame.Audio -> play(frame)
        }
    }

    private fun play(frame: StageFrame.Audio) {
        when (frame.codec) {
            StageFrameDecoder.CODEC_LPCM -> sink.write(frame.codec, frame.payload)
            StageFrameDecoder.CODEC_AC3_FMP4 -> {
                if (!ac3Mode) return
                StageFragments.samples(frame.payload)?.forEach { sink.write(StageFrameDecoder.CODEC_AC3_FMP4, it) }
            }
            else -> return
        }
    }

    companion object {
        private const val NORMAL_CLOSE = 1000
    }
}

/** Retry delays for the stage socket, which the controller on the web also uses: 1 s, doubling, capped at 30 s. */
internal fun stageRetryDelayMs(attempt: Int): Long = (1_000L shl attempt.coerceIn(0, 5)).coerceAtMost(30_000L)
