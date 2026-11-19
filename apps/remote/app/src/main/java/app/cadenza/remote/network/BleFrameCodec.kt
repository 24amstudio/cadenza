package app.cadenza.remote.network

import java.nio.ByteBuffer

/**
 * Frames are a 4-byte big-endian length followed by the payload, split across characteristic values.
 *
 * The stream has no markers to resync on, so a lost fragment cannot be skipped: the declared length would swallow the
 * frames behind it. A frame that stops growing is therefore treated as damaged and the caller ends the link, which
 * makes the session reconnect from a clean state instead of staying silent behind a frame that can never finish.
 */
internal class BleFrameCodec(
    private val nowMs: () -> Long = { System.nanoTime() / 1_000_000 },
) {
    private var storage = ByteArray(INITIAL_BYTES)
    private var start = 0
    private var end = 0
    private var expected = -1
    private var lastProgressMs = 0L

    fun encode(
        payload: ByteArray,
        mtu: Int,
    ): List<ByteArray> {
        require(payload.size <= MAXIMUM_FRAME_BYTES) { "BLE frame is too large." }
        val framed =
            ByteBuffer
                .allocate(payload.size + HEADER_BYTES)
                .putInt(payload.size)
                .put(payload)
                .array()
        val chunkSize = (mtu - ATT_HEADER_BYTES).coerceAtLeast(MINIMUM_CHUNK_BYTES)
        return (framed.indices step chunkSize).map { framed.copyOfRange(it, minOf(it + chunkSize, framed.size)) }
    }

    /** Returns every frame completed by [chunk]. A damaged stream throws and leaves the codec empty. */
    fun append(chunk: ByteArray): List<ByteArray> {
        val now = nowMs()
        if ((expected >= 0 || end > start) && now - lastProgressMs > STALLED_FRAME_MS) {
            reset()
            throw IllegalStateException("Bluetooth frame stalled before it was complete.")
        }
        lastProgressMs = now
        reserve(chunk.size)
        chunk.copyInto(storage, end)
        end += chunk.size
        val frames = mutableListOf<ByteArray>()
        while (true) {
            if (expected < 0) {
                if (end - start < HEADER_BYTES) return frames
                val length = ByteBuffer.wrap(storage, start, HEADER_BYTES).int
                if (length !in 0..MAXIMUM_FRAME_BYTES) {
                    reset()
                    throw IllegalStateException("BLE frame length is invalid.")
                }
                expected = length
                start += HEADER_BYTES
            }
            if (end - start < expected) return frames
            frames += storage.copyOfRange(start, start + expected)
            start += expected
            expected = -1
        }
    }

    private fun reset() {
        start = 0
        end = 0
        expected = -1
    }

    // Unread bytes move to the front, or into a larger buffer if they still do not fit. Copying the whole backlog for
    // every 244-byte value would make a large browse result quadratic in the number of notifications.
    private fun reserve(extra: Int) {
        if (end + extra <= storage.size) return
        val pending = end - start
        val target = if (pending + extra > storage.size) ByteArray(maxOf(storage.size * 2, pending + extra)) else storage
        storage.copyInto(target, 0, start, end)
        storage = target
        start = 0
        end = pending
    }

    companion object {
        const val MAXIMUM_FRAME_BYTES = 1_048_576
        const val STALLED_FRAME_MS = 10_000L
        private const val HEADER_BYTES = 4
        private const val ATT_HEADER_BYTES = 3
        private const val MINIMUM_CHUNK_BYTES = 20
        private const val INITIAL_BYTES = 4_096
    }
}
