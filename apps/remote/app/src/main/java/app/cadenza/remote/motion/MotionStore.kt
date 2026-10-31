package app.cadenza.remote.motion

import java.io.File
import java.io.IOException

// Verified motion files stay in app-private storage under their digest. Only the file for the current song is kept.
internal class MotionStore(
    private val directory: File,
) {
    /** Writes the verified bytes atomically and removes every other motion file. */
    fun save(
        sha256: String,
        bytes: ByteArray,
    ): File {
        directory.mkdirs()
        val target = File(directory, "$sha256.mp4")
        if (!target.exists()) {
            val temporary = File(directory, "$sha256.part")
            temporary.writeBytes(bytes)
            if (!temporary.renameTo(target)) {
                temporary.delete()
                throw IOException("Motion artwork could not be stored.")
            }
        }
        directory.listFiles()?.forEach { if (it != target) it.delete() }
        return target
    }
}
