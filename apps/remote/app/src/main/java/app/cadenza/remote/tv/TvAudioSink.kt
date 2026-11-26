package app.cadenza.remote.tv

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Plays the stage's audio through one low-latency `AudioTrack`. Writes block, so they run on a background dispatcher and
 * never on the main thread. Raw float PCM goes out as stereo or 5.1. AC-3 syncframes
 * go out in passthrough, which reaches the AVR over HDMI when the output reports AC-3. A flush empties the track in
 * `pause`, `flush`, `play` order, so the next frame starts at once.
 */
internal class TvAudioSink {
    private var track: AudioTrack? = null
    private var mode: Mode? = null

    /** What the open track plays: its codec, its channel count, and the path it takes. Null when no track is open. */
    var route: Route? = null
        private set

    data class Route(
        val codec: String,
        val channels: Int,
        val path: String,
    )

    private enum class Mode { PCM, AC3 }

    /** True while the open track is playing. It is false when the track is paused or none is open. */
    fun isPlaying(): Boolean = track?.playState == AudioTrack.PLAYSTATE_PLAYING

    /** Starts or restarts the track for a codec and layout. A layout that is already playing keeps its track. */
    fun configure(
        codec: Int,
        channels: Int,
        sampleRate: Int,
    ): Boolean {
        val nextMode = if (codec == StageFrameDecoder.CODEC_AC3_FMP4) Mode.AC3 else Mode.PCM
        val mask = channelMask(channels, nextMode) ?: return false
        if (mode == nextMode && track?.channelCount == channelCount(mask)) return true
        release()
        val encoding = if (nextMode == Mode.AC3) AudioFormat.ENCODING_AC3 else AudioFormat.ENCODING_PCM_FLOAT
        val format =
            AudioFormat
                .Builder()
                .setEncoding(encoding)
                .setSampleRate(sampleRate)
                .setChannelMask(mask)
                .build()
        track =
            AudioTrack
                .Builder()
                .setAudioAttributes(
                    AudioAttributes
                        .Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build(),
                ).setAudioFormat(format)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                .build()
        mode = nextMode
        route =
            if (nextMode == Mode.AC3) {
                Route("ac3", channelCount(mask), "audiotrack_ac3")
            } else {
                Route("pcm", channelCount(mask), "audiotrack_pcm")
            }
        track?.play()
        return true
    }

    /** Writes one frame's payload. Float PCM is little-endian, as the Host writes it. */
    fun write(
        codec: Int,
        payload: ByteArray,
    ) {
        val current = track ?: return
        if (codec == StageFrameDecoder.CODEC_LPCM) {
            val floats = FloatArray(payload.size / 4)
            ByteBuffer
                .wrap(payload)
                .order(ByteOrder.LITTLE_ENDIAN)
                .asFloatBuffer()
                .get(floats)
            current.write(floats, 0, floats.size, AudioTrack.WRITE_BLOCKING)
        } else {
            current.write(payload, 0, payload.size, AudioTrack.WRITE_BLOCKING)
        }
    }

    /** Drops everything queued. The track keeps its configuration, so the next frame plays at once. */
    fun flush() {
        val current = track ?: return
        current.pause()
        current.flush()
        current.play()
    }

    fun release() {
        track?.runCatching {
            stop()
            release()
        }
        track = null
        mode = null
        route = null
    }

    private fun channelMask(
        channels: Int,
        mode: Mode,
    ): Int? =
        when {
            mode == Mode.AC3 && channels == 6 -> AudioFormat.CHANNEL_OUT_5POINT1
            mode == Mode.PCM && channels == 2 -> AudioFormat.CHANNEL_OUT_STEREO
            mode == Mode.PCM && channels == 6 -> AudioFormat.CHANNEL_OUT_5POINT1
            else -> null
        }

    /** An output mask has one bit per channel, so its set bits are the channel count. */
    private fun channelCount(mask: Int): Int = Integer.bitCount(mask)

    companion object {
        /** The AC-3 encodings an output reports. Passthrough needs one of them, so the profile lists AC-3 only then. */
        fun supportsAc3(encodings: Collection<Int>): Boolean = AudioFormat.ENCODING_AC3 in encodings
    }
}
