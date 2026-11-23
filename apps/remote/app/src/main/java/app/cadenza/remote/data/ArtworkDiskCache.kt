package app.cadenza.remote.data

import java.io.File
import java.security.MessageDigest

internal const val ARTWORK_DISK_BYTES = 32L * 1024 * 1024

// Cover bytes kept across restarts. Each file is named by a digest of its address, and the least recently used files
// are removed once the total passes [maxBytes], so the cache stays bounded.
internal class ArtworkDiskCache(
    private val directory: File,
    private val maxBytes: Long,
    private val now: () -> Long = System::currentTimeMillis,
) {
    @Synchronized
    fun get(url: String): ByteArray? {
        val file = fileFor(url)
        if (!file.isFile) return null

        file.setLastModified(now())

        return runCatching { file.readBytes() }.getOrNull()
    }

    @Synchronized
    fun put(
        url: String,
        bytes: ByteArray,
    ) {
        if (bytes.size > maxBytes) return

        directory.mkdirs()
        val file = fileFor(url)
        val written = runCatching { file.writeBytes(bytes) }.isSuccess
        if (!written) {
            file.delete()
            return
        }
        file.setLastModified(now())
        evict()
    }

    private fun evict() {
        val files = directory.listFiles()?.filter { it.isFile }.orEmpty()
        var total = files.sumOf { it.length() }

        for (file in files.sortedBy { it.lastModified() }) {
            if (total <= maxBytes) return

            total -= file.length()
            file.delete()
        }
    }

    private fun fileFor(url: String): File {
        val digest = MessageDigest.getInstance("SHA-256").digest(url.toByteArray(Charsets.UTF_8))

        return File(directory, digest.joinToString("") { "%02x".format(it) })
    }
}
