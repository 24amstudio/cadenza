package app.cadenza.remote.tv

import java.nio.ByteBuffer

/**
 * The binary stage frames, as `shared/protocol/README.md` defines them. Integers are big-endian. Every decoder in the
 * Host, the web stage, and this receiver accepts the same bytes from `shared/protocol/examples/cast-stage-frames.json`.
 */
internal sealed interface StageFrame {
    data class Audio(
        val codec: Int,
        val channels: Int,
        val sampleRate: Int,
        val presentationTimeUs: Long,
        val payload: ByteArray,
    ) : StageFrame

    data class InitSegment(
        val codec: Int,
        val channels: Int,
        val sampleRate: Int,
        val payload: ByteArray,
    ) : StageFrame

    data class Flush(
        val generationSeq: Long,
    ) : StageFrame
}

internal class StageFrameException(
    message: String,
) : Exception(message)

internal object StageFrameDecoder {
    const val AUDIO_TYPE = 0x01
    const val FLUSH_TYPE = 0x02
    const val INIT_TYPE = 0x03
    const val MAX_PAYLOAD_BYTES = 65_536
    const val CODEC_AC3_FMP4 = 1
    const val CODEC_LPCM = 3
    const val CODEC_AAC_FMP4 = 4

    private val codecs = setOf(1, 2, 3, 4)
    private val sampleRates = mapOf(1 to 48_000, 2 to 44_100)

    fun decode(bytes: ByteArray): StageFrame {
        if (bytes.isEmpty()) throw StageFrameException("empty frame")
        val buffer = ByteBuffer.wrap(bytes)
        return when (buffer.get(0).toInt() and 0xFF) {
            FLUSH_TYPE -> decodeFlush(bytes, buffer)
            INIT_TYPE -> decodeInit(bytes, buffer)
            AUDIO_TYPE -> decodeAudio(bytes, buffer)
            else -> throw StageFrameException("unknown frame type")
        }
    }

    private fun decodeFlush(
        bytes: ByteArray,
        buffer: ByteBuffer,
    ): StageFrame {
        if (bytes.size != 5) throw StageFrameException("flush frame must be 5 bytes")
        return StageFrame.Flush(buffer.getInt(1).toLong() and 0xFFFF_FFFFL)
    }

    private fun decodeInit(
        bytes: ByteArray,
        buffer: ByteBuffer,
    ): StageFrame {
        if (bytes.size < 8) throw StageFrameException("init segment header is truncated")
        val codec = header(buffer, 1)
        val channels = header(buffer, 2)
        val rateCode = header(buffer, 3)
        val length = buffer.getInt(4).toLong() and 0xFFFF_FFFFL
        checkHeader(codec, channels, rateCode)
        if (length > MAX_PAYLOAD_BYTES) throw StageFrameException("payload exceeds the frame limit")
        if (bytes.size - 8 != length.toInt()) throw StageFrameException("payload length does not match the frame")
        return StageFrame.InitSegment(codec, channels, sampleRates.getValue(rateCode), bytes.copyOfRange(8, bytes.size))
    }

    private fun decodeAudio(
        bytes: ByteArray,
        buffer: ByteBuffer,
    ): StageFrame {
        if (bytes.size < 16) throw StageFrameException("audio frame header is truncated")
        val codec = header(buffer, 1)
        val channels = header(buffer, 2)
        val rateCode = header(buffer, 3)
        val timestamp = buffer.getLong(4)
        val length = buffer.getInt(12).toLong() and 0xFFFF_FFFFL
        checkHeader(codec, channels, rateCode)
        if (length > MAX_PAYLOAD_BYTES) throw StageFrameException("payload exceeds the frame limit")
        if (bytes.size - 16 != length.toInt()) throw StageFrameException("payload length does not match the frame")
        return StageFrame.Audio(
            codec = codec,
            channels = channels,
            sampleRate = sampleRates.getValue(rateCode),
            presentationTimeUs = timestamp,
            payload = bytes.copyOfRange(16, bytes.size),
        )
    }

    private fun header(
        buffer: ByteBuffer,
        index: Int,
    ): Int = buffer.get(index).toInt() and 0xFF

    private fun checkHeader(
        codec: Int,
        channels: Int,
        rateCode: Int,
    ) {
        if (codec !in codecs) throw StageFrameException("unknown codec")
        if (channels !in 1..8) throw StageFrameException("channel count out of range")
        if (rateCode !in sampleRates) throw StageFrameException("unknown sample rate code")
    }
}
