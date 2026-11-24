package app.cadenza.remote.media

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack

/**
 * Loops one silent buffer while the Host plays. It does not take audio focus, and a static buffer costs almost nothing to
 * keep playing. Its purpose is to mark the app as doing media work, so HarmonyOS does not treat it as an idle socket app.
 */
class SilentPlaybackKeepAlive {
    private var track: AudioTrack? = null

    fun update(playing: Boolean) {
        if (playing) {
            if (track == null) track = createTrack()?.also { it.play() }
            return
        }
        track?.let {
            it.stop()
            it.release()
        }
        track = null
    }

    private fun createTrack(): AudioTrack? =
        try {
            val frames = SAMPLE_RATE / 10
            AudioTrack
                .Builder()
                .setAudioAttributes(
                    AudioAttributes
                        .Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                ).setAudioFormat(
                    AudioFormat
                        .Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                ).setBufferSizeInBytes(frames * 2)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()
                .also {
                    it.write(ShortArray(frames), 0, frames)
                    it.setLoopPoints(0, frames, -1)
                }
        } catch (error: RuntimeException) {
            null
        }

    private companion object {
        const val SAMPLE_RATE = 8_000
    }
}
