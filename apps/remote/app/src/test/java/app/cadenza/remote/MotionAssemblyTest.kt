package app.cadenza.remote

import app.cadenza.remote.motion.MotionAssembly
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest

class MotionAssemblyTest {
    private val video = ByteArray(1_000) { (it % 251).toByte() }
    private val digest = sha256(video)

    @Test
    fun aVerifiedFileIsRebuiltWhateverTheChunkOrder() {
        val assembly = requireNotNull(MotionAssembly.open("occurrence", 2, video.size, digest))

        assertTrue(assembly.accept(1, video.copyOfRange(600, 1_000)))
        assertTrue(assembly.accept(0, video.copyOfRange(0, 600)))
        assertArrayEquals(video, assembly.assemble())
    }

    @Test
    fun aTamperedOrTruncatedTransferIsNeverReturned() {
        val tampered = requireNotNull(MotionAssembly.open("occurrence", 2, video.size, digest))
        tampered.accept(0, video.copyOfRange(0, 600))
        tampered.accept(1, ByteArray(400) { 9 })
        assertNull(tampered.assemble())

        val truncated = requireNotNull(MotionAssembly.open("occurrence", 2, video.size + 1, digest))
        truncated.accept(0, video.copyOfRange(0, 600))
        truncated.accept(1, video.copyOfRange(600, 1_000))
        assertNull(truncated.assemble())
    }

    @Test
    fun repeatedOrOutOfRangeChunksAreRefused() {
        val assembly = requireNotNull(MotionAssembly.open("occurrence", 2, video.size, digest))

        assertTrue(assembly.accept(0, video.copyOfRange(0, 600)))
        assertFalse(assembly.accept(0, video.copyOfRange(0, 600)))
        assertFalse(assembly.accept(2, video.copyOfRange(600, 1_000)))
        assertFalse(assembly.complete)
    }

    @Test
    fun aTransferOutsideTheProtocolLimitsIsNotOpened() {
        assertNull(MotionAssembly.open("occurrence", 0, 10, digest))
        assertNull(MotionAssembly.open("occurrence", 1, 9_000_000, digest))
        assertNull(MotionAssembly.open("occurrence", 1, 10, "not-a-digest"))
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
}
