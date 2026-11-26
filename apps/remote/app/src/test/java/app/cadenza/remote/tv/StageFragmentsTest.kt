package app.cadenza.remote.tv

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.nio.ByteBuffer

class StageFragmentsTest {
    private fun box(
        type: String,
        payload: ByteArray,
    ): ByteArray =
        ByteBuffer
            .allocate(8 + payload.size)
            .putInt(8 + payload.size)
            .put(type.toByteArray(Charsets.ISO_8859_1))
            .put(payload)
            .array()

    /** A fragment as the Host writes it: one `trun` with explicit sizes and a data offset into `mdat`. */
    private fun fragment(samples: List<ByteArray>): ByteArray {
        fun trunBox(dataOffset: Int): ByteArray {
            val body =
                ByteBuffer
                    .allocate(12 + 8 * samples.size)
                    .putInt(0x000301)
                    .putInt(samples.size)
                    .putInt(dataOffset)
            samples.forEach { body.putInt(1_024).putInt(it.size) }
            return box("trun", body.array())
        }

        fun moofWith(dataOffset: Int): ByteArray =
            box("moof", box("mfhd", ByteArray(8)) + box("traf", box("tfhd", ByteArray(8)) + trunBox(dataOffset)))

        // The data offset counts from the start of `moof`, and the samples follow the 8-byte `mdat` header.
        val moofSize = moofWith(0).size
        val mdat = box("mdat", samples.fold(ByteArray(0)) { acc, sample -> acc + sample })
        return moofWith(moofSize + 8) + mdat
    }

    @Test
    fun theSamplesComeBackInOrderWithTheirExactBytes() {
        val first = byteArrayOf(0x0B, 0x77, 1, 2, 3)
        val second = byteArrayOf(0x0B, 0x77, 9, 8)
        val samples = StageFragments.samples(fragment(listOf(first, second)))
        assertArrayEquals(first, samples!![0])
        assertArrayEquals(second, samples[1])
    }

    @Test
    fun aFragmentWithoutItsBoxesIsRejected() {
        assertNull(StageFragments.samples(box("free", ByteArray(4))))
    }
}
