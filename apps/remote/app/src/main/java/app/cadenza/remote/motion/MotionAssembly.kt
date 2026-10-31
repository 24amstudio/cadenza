package app.cadenza.remote.motion

import java.security.MessageDigest

// The Host sends the MP4 in bounded chunks. The file is used only after every chunk arrived once and the whole file
// matches the Host's SHA-256 digest, so a damaged or truncated transfer is never shown.
internal class MotionAssembly private constructor(
    val occurrenceId: String,
    val sha256: String,
    private val totalBytes: Int,
    private val chunks: Array<ByteArray?>,
) {
    private var received = 0

    val complete: Boolean get() = received == chunks.size

    /** Stores one chunk. Returns false for an out-of-range, repeated, empty, or oversized chunk. */
    fun accept(
        index: Int,
        bytes: ByteArray,
    ): Boolean {
        if (index !in chunks.indices || chunks[index] != null || bytes.isEmpty() || bytes.size > CHUNK_BYTES) return false
        chunks[index] = bytes
        received++
        return true
    }

    /** The verified file, or null when the sizes or digest differ from what the Host announced. */
    fun assemble(): ByteArray? {
        if (!complete) return null
        val parts = chunks.filterNotNull()
        val size = parts.sumOf { it.size }
        if (size != totalBytes) return null
        val file = ByteArray(size)
        var offset = 0
        for (part in parts) {
            part.copyInto(file, offset)
            offset += part.size
        }
        val digest = MessageDigest.getInstance("SHA-256").digest(file).joinToString("") { "%02x".format(it) }
        return file.takeIf { digest == sha256 }
    }

    companion object {
        // Matches the Host's chunk size. Two chunks of this size stay well under the 1 MiB message limit once base64 encoded.
        const val CHUNK_BYTES = 480 * 1_024
        private const val MAXIMUM_CHUNKS = 4_096
        private const val MAXIMUM_BYTES = 8 * 1_048_576
        private val digestPattern = Regex("[0-9a-f]{64}")

        /** Opens a transfer only when the Host's announced count, size, and digest are within the protocol limits. */
        fun open(
            occurrenceId: String,
            chunkCount: Int,
            totalBytes: Int,
            sha256: String,
        ): MotionAssembly? {
            if (chunkCount !in 1..MAXIMUM_CHUNKS || totalBytes !in 1..MAXIMUM_BYTES || !digestPattern.matches(sha256)) {
                return null
            }
            return MotionAssembly(occurrenceId, sha256, totalBytes, arrayOfNulls(chunkCount))
        }
    }
}
